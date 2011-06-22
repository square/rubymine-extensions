def log(msg)
  File.open("/tmp/log", "a") { |f| f << "* #{msg}\n" }
end

def try
  begin
    yield
  rescue Exception => e
    log "Error! #{e.message}\n#{e.backtrace.join("\n")}"
  end
end

log("here we are!")

def load_lib
  log("Loading libraries...")
  Dir[File.join(File.dirname(__FILE__), "lib", "*.rb")].sort.each do |fn|
    log("Loading #{fn}...")
    try { load(fn) }
  end
end

def load_plugins
  log("Loading plugins...")
  Dir[File.join(File.dirname(__FILE__), "plugins", "*", "*.rb")].sort.each do |fn|
    log("Loading #{fn}...")
    try { load(fn) }
  end
end

def reload
  log("reload! #{__FILE__}")
  try { load(__FILE__) }
end

try {
  register_editor_action "reread_extensions",
                         :text                    => "Reread extensions",
                         :description             => "Converts a string in CamelCase to snake_case and vice versa.",
                         :group                   => ["EditorActions", {:id                 => "EditSmartGroup",
                                                                        :anchor             => 'after',
                                                                        :relative_to_action => 'EditorToggleCase'}],
                         :enable_in_modal_context => true,
                         :shortcut                => "control alt R" do |editor, file|
    log("reload!")
    try { ExtBase.uninstall_all }
    try { reload }
  end
}

load_lib
load_plugins