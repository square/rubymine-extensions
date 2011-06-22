puts 'Hello PMIP 0.3.1! - Please see http://code.google.com/p/pmip/ for full instructions and plugin helper bundles.'

class RspecContext < ExtBase
  def initialize
    @project_tool_wins      = {}
    @editor_caret_listeners = {}
    @list_clicked_at        = Time.at(0)
  end

  def hear_project(project, registry)
    ProjectHandler.new(project, registry)
  end

  def project_opened(project)
    tool_win(project).populate(self)
  end

  def project_closed(project)
  end

  def tool_win(project)
    @project_tool_wins[project] ||= ToolWin.new(project, "rspec context")
  end

  def editor_created(editor)
    psi_file = ExtBase.psi_file(editor)
    return unless psi_file
    if psi_file.name =~ /(spec|shared).rb/
      @editor_caret_listeners[editor] = caret_listener = CaretListener.new(self, editor)
      editor.caret_model.add_caret_listener(caret_listener)
    end
  end

  def editor_destroyed(editor)
    listener = @editor_caret_listeners.delete(editor)
    editor.caret_model.remove_caret_listener(listener) if listener
  end

  def update(editor)
    return if Time.now - @list_clicked_at < 1

    psi_file  = ExtBase.psi_file(editor)
    offset    = editor.caret_model.offset
    selection = psi_file.find_element_at(offset)

    spec_context = SpecContext.new(editor)
    spec_context.find_outer_contexts(selection)
    spec_context.show_lets(tool_win(editor.project))
  end

  def list_clicked
    @list_clicked_at = Time.now
  end

  class CaretListener
    def initialize(context, editor)
      @context   = context
      @tool_win  = context.tool_win(editor.project)
      @last_time = Time.at(0)
      @thread    = nil
    end

    def caret_position_changed(event)
      try {
        last_time = @last_time
        now       = Time.now
        if now - last_time < 0.5
          return if @thread
          @thread = Thread.new {
            sleep(now - last_time)
            ExtBase::Run.later {
              @context.update(event.editor)
              @thread = nil
            }
          }
        else
          @context.update(event.editor)
          @last_time = now
        end
      }
    end
  end

  class ToolWin < ExtBase::ToolWin
    def populate(context)
      import javax.swing.JList
      import javax.swing.DefaultListModel
      import javax.swing.ListSelectionModel
      import com.intellij.ui.content.ContentFactory

      @list_model          = DefaultListModel.new
      @list                = JList.new(@list_model)
      @list.selection_mode = ListSelectionModel.SINGLE_SELECTION
      @list.add_list_selection_listener(ListSelectionListener.new(context))
#      @list.cell_renderer = MyListCellRenderer.new

      window.content_manager.remove_all_contents(true)
      @content = ContentFactory::SERVICE.instance.create_content(@list, "", true)
      window.content_manager.add_content(@content)
    end

    def add_item(item)
      @list_model.add_element(item)
    end

    def clear_items
      @list_model.remove_all_elements
    end

    def set_items(items)
      clear_items
      items.each { |item| add_item(item) }
    end
  end

  class SpecContext
    def initialize(editor)
      @lets    = {}
      @befores = []
      @editor  = editor
    end

    def is_block?(psi_element)
      ast_node = psi_element.node
      return false unless ast_node
      ast_node.element_type.to_s =~ /Ruby:.* block call/
    end

    def find_outer_contexts(selection)
      return unless selection
      parent = selection.parent
      return unless parent

      parent.children.each do |el|
        if is_block?(el)
          if el.text =~ /^(let|subject)/
            process_let_or_subject(el)
          elsif el.text =~ /^before/
            process_before(el)
          end
        end
      end

      find_outer_contexts(parent)
    end

    def process_let_or_subject(el)
      if el.text =~ /^let/
        left = el.children[0]
        let  = left.children[0].text
        name = left.children[1].text
      else
        let  = nil
        name = "subject"
      end

      block = el.children[1].text

      @lets[name] ||= [let, block, el.text_offset]
    end

    def process_before(el)
      @befores.unshift([el.text, el.text_offset])
    end

    def show_lets(tool_win)
      tool_win.clear_items

      @lets.keys.sort.each do |key|
        let, block, offset = @lets[key]
        if let
          tool_win.add_item(ListItem.new(:let, "#{let}(#{key}) #{block}", offset, @editor))
        else
          tool_win.add_item(ListItem.new(:subject, "subject #{block}", offset, @editor))
        end
      end

      tool_win.add_item("---")

      @befores.each do |before, offset|
        tool_win.add_item(ListItem.new(:before, before, offset, @editor))
      end
    end
  end

  class ListSelectionListener
    def initialize(context)
      @context = context
    end

    def value_changed(event)
      try {
        @context.list_clicked
#      return if event.value_is_adjusting?
        index = event.source.selection_model.min_selection_index
        return if index == -1
        list_item = event.source.model.get(index)
        list_item.select
      }
    end
  end

  class ListItem
    def initialize(type, text, offset, editor)
      @type   = type
      @text   = text
      @offset = offset
      @editor = editor
    end

    def select
      puts @offset
      @editor.caret_model.move_to_offset(@offset)

      import com.intellij.openapi.editor.ScrollType
      @editor.scrolling_model.scroll_to_caret(ScrollType::MAKE_VISIBLE);
    end

    def to_s
      @text.gsub(/\n/, "; ")
    end
  end

  class MyListCellRenderer
    def list_cell_renderer_component(jlist, o, i, b1, b2)
      puts "render!"
    end
  end

end

##  unless @already_ran
#import com.intellij.openapi.editor.EditorFactory
#
#editor_factory = EditorFactory.instance
#editor_factory.add_editor_factory_listener(RspecContext::EditorFactoryListener.new)
#log("added editor factory listener!")
#
#log(RspecContext.projects.size)
#RspecContext.projects.each { |project| RspecContext::ToolWin.create(project, "rspec context") }
#
#@already_ran = true
##  end
#
#RspecContext::ToolWin.populate

ExtBase.register(RspecContext.new)