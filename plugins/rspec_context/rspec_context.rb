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

  def editor_released(editor)
    listener = @editor_caret_listeners.delete(editor)
    editor.caret_model.remove_caret_listener(listener) if listener
  end

  def update(editor)
    return if Time.now - @list_clicked_at < 1

    psi_file  = ExtBase.psi_file(editor)
    offset    = editor.caret_model.offset
    selection = psi_file.find_element_at(offset)
    if selection.text =~ /^[\s]+$/
      selection = psi_file.find_element_at(editor.caret_model.visual_line_end)
    end

    spec_context = ContextBuilder.new(editor)
    spec_context.search_scope(selection)
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
        if now - last_time < 0.3
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
      @list.cell_renderer = MyListCellRenderer.new

      window.content_manager.remove_all_contents(true)
      scroll_view = javax.swing.JScrollPane.new(@list)
      @content    = ContentFactory::SERVICE.instance.create_content(scroll_view, "", true)
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

  class ContextBuilder
    def initialize(editor)
      @lets        = {}
      @befores     = []
      @description = []
      @editor      = editor
    end

    def is_block?(psi_element)
      ast_node = psi_element.node
      return false unless ast_node
      ast_node.element_type.to_s =~ /Ruby:.* block call/
    end

    def block_of(psi_element)
      psi_element = psi_element.children[psi_element.children.length - 1]
      psi_element.children[psi_element.children.length - 1]
    end

    def enclosing_block(selection)
      original = selection
      selection = selection.parent until !selection || is_block?(selection)
      selection = block_of(selection) if selection
      selection || original
    end

    def search_scope(selection)
      selection = enclosing_block(selection)
      search_scope_and_ascend(selection)
    end

    def search_scope_and_ascend(selection)
      return unless selection

      selection.children.each do |el|
        if is_block?(el)
          if el.text =~ /^(let|subject)/
            process_let_or_subject(el)
          elsif el.text =~ /^before/
            process_before(el)
          end
        end
      end

      if is_block?(selection) && selection.text =~ /^(context|describe|it)/
        process_context(selection)
      end

      search_scope_and_ascend(selection.parent)
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

    def process_context(el)
      @description.unshift([el.children[0].children[1].text.gsub(/^"/, '').gsub(/"$/, ''), el.text_offset])
    end

    def show_lets(tool_win)
      tool_win.clear_items

      @lets.keys.sort.each do |key|
        let, block, offset = @lets[key]
        if let
          tool_win.add_item(ListItem.new(:let, offset, @editor, :let => let, :key => key, :block => block))
        else
          tool_win.add_item(ListItem.new(:subject, offset, @editor, :block => block))
        end
      end

      tool_win.add_item("---")

      @befores.each do |before, offset|
        tool_win.add_item(ListItem.new(:before, offset, @editor, :block => before))
      end

      tool_win.add_item("---")

      tool_win.add_item(ListItem.new(:description, @editor.caret_model.offset, @editor, :contexts => @description))
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
    def initialize(item_type, offset, editor, data = {})
      @item_type = item_type
      @offset    = offset
      @editor    = editor
      @data      = data
    end

    attr_accessor :item_type, :data

    def select
      return unless @offset
      @editor.caret_model.move_to_offset(@offset)

      import com.intellij.openapi.editor.ScrollType
      @editor.scrolling_model.scroll_to_caret(ScrollType::MAKE_VISIBLE);
    end

    def to_s
      @text.gsub(/\n/, "; ")
    end
  end

  class MyListCellRenderer
    def initialize
      @delegate = javax.swing.DefaultListCellRenderer.new
    end

    def two_columns(left, right, left_is_red)
      left_length = left.length
      "<b#{left_is_red ? " style=\"color: red;\"" : ""}>#{left.gsub(/ /, "&nbsp;")}</b>#{"&nbsp;" * ([28 - left_length, 0].max)} #{right}"
    end

    def block(data)
      data[:block].
        gsub(/([\{\[\(])\s\s+/, '\1 ').
        gsub(/\s\s+([\}\]\)])/, ' \1').
        gsub(/\s*\n\s*/, ' <b style="color: blue;">¶</b> ')
    end

    def get_list_cell_renderer_component(jlist, obj, index, is_selected, has_focus)
      if obj.is_a?(String)
        msg = obj
      else
        data = obj.data
        msg  = case obj.item_type
          when :let
            let = data[:let]
            if let == "let!"
              red = true
            else
              red = false
              let = "let "
            end
            left = "#{let}#{data[:key]}"
            two_columns(left, block(data), red)
          when :subject
            two_columns("subject", block(data), false)
          when :before
            block(data)
          when :description
            parts = data[:contexts].map { |context, offset| context }
            parts << "<b>#{parts.pop}</b>"
            "<i>Spec:</i> #{parts.join(" <b>→</b> ")}"
               end

        msg = "<span style=\"font-family: monospace;\">#{msg}</span>"
      end
      pane = javax.swing.JEditorPane.new("text/html", msg)
      pane.background = java.awt.Color::GREEN if is_selected
      return pane
    rescue Exception => e
      log(e)
      @delegate.get_list_cell_renderer_component(jlist, msg, index, is_selected, has_focus)
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