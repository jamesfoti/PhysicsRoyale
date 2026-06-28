import bpy

ADDON_PATH: str = r"c:\Dev\solar_system_demo\tools\blender_mcp\addon.py"
MODULE_NAME: str = "addon"


def main() -> None:
	bpy.ops.preferences.addon_install(filepath=ADDON_PATH, overwrite=True)
	bpy.ops.preferences.addon_enable(module=MODULE_NAME)
	bpy.ops.wm.save_userpref()
	print(f"Installed and enabled Blender MCP addon ({MODULE_NAME}).")


if __name__ == "__main__":
	main()
