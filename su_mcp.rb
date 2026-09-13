require 'sketchup.rb'
require 'extensions.rb'
require 'json'
require 'socket'

module SU_MCP
  unless file_loaded?(__FILE__)
    ex = SketchupExtension.new('SketchUp MCP (NeoNexAI)', 'su_mcp/su_mcp/bootstrap')
    ex.description = 'MCP server for SketchUp — hardened fork with architecture, storefront, multi-storey, stair, and roof tools; no arbitrary code execution'
    ex.version     = '1.8.0'
    ex.copyright   = '2026'
    Sketchup.register_extension(ex, true)
    file_loaded(__FILE__)
  end
end
