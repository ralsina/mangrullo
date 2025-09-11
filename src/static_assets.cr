require "baked_file_system"

class StaticAssets
  extend BakedFileSystem
  bake_folder "../public"
end