class ExtBase
  import com.intellij.openapi.project.ProjectManager

  class << self
    def register(plugin)
      @@plugins ||= []
      @@plugins << plugin
      plugin.listen
    end

    def uninstall_all
      return unless defined? @@plugins
      @@plugins.each { |plugin| try { plugin.uninstall } }
      @@plugins.clear
    end

    def psi_file(editor)
      com.intellij.psi.PsiDocumentManager.get_instance(editor.project).get_psi_file(editor.document)
    end
  end

  def editor_factory
    com.intellij.openapi.editor.EditorFactory.instance
  end

  def project_manager
    com.intellij.openapi.project.ProjectManager.instance
  end

  def listen
    @listener = Listener.new(self)

    try {
      editor_factory.add_editor_factory_listener(@listener)
      project_manager.add_project_manager_listener(@listener)
    }

    project_manager.open_projects.each { |project| @listener.project_opened(project) }
    editor_factory.all_editors.each { |editor| @listener.editor_created(editor) }
  end

  def uninstall
    return unless @listener

    editor_factory.all_editors.each { |editor| @listener.editor_released(editor) }
    project_manager.open_projects.each { |project| @listener.project_closed(project) }

    try {
      editor_factory.remove_editor_factory_listener(@listener)
      project_manager.remove_project_manager_listener(@listener)
    }
  end

  class Listener
    include com.intellij.openapi.editor.event.EditorFactoryListener
    include com.intellij.openapi.project.ProjectManagerListener

    def initialize(delegate)
      @delegate = delegate
    end

    def self.delegate_to(method)
      define_method(method) do |*args|
        try do
          if @delegate.respond_to?(method)
            args = yield *args if block_given?
            @delegate.__send__(method, *args)
          end
        end
      end
    end

    [:project_opened, :project_closed].each do |method|
      delegate_to(method)
    end

    [:editor_created, :editor_released].each do |method|
      delegate_to(method) { |editor_or_event| [editor_or_event.respond_to?(:editor) ? editor_or_event.editor : editor_or_event] }
    end
  end

  class ToolWin
    import com.intellij.openapi.wm.ToolWindowAnchor
    import com.intellij.openapi.wm.ToolWindowManager

    def initialize(project, name)
      @project = project
      @name    = name

      tool_window_manager = ToolWindowManager.get_instance(project)
      @window             = tool_window_manager.get_tool_window(name)
      @window             ||= tool_window_manager.register_tool_window(name, true, ToolWindowAnchor::BOTTOM)
    end

    def window
      @window
    end
  end


  class RunnableBlock
    include java.lang.Runnable

    def initialize(block)
      @block = block
    end

    def run
      @block.call
    end
  end

  class Run
    def self.application
      com.intellij.openapi.application.ApplicationManager.application
    end

    def self.on_pooled_thread(&block)
      application.executeOnPooledThread(RunnableBlock.new(block))
    end

    def self.later(&block)
      application.invokeLater(RunnableBlock.new(block))
    end

    def self.read_action(&block)
      application.runReadAction(RunnableBlock.new(block))
    end

    def self.write_action(&block)
      application.runWriteAction(RunnableBlock.new(block))
    end
  end
end
