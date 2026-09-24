require 'sketchup.rb'
require 'extensions.rb'
require 'json'
require 'socket'

module SU_MCP
  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('OpenSU', 'su_mcp/su_mcp/bootstrap')
    ex.description = 'Open-source AI modeling agent bridge for SketchUp — architecture, drawing reconstruction, persistent building semantics, grid-driven layout, hierarchical semantic grouping, diagnostics, and controlled repair; no arbitrary code execution'
    ex.version     = '1.15.0'
    ex.copyright   = '2026'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end
end
