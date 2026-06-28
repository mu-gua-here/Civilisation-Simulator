extends Node3D

# ENSURE CONSISTENT LIGHTING BETWEEN RENDERERS

# Detect renderer and change
func _ready():
	
	var env_path := "res://scenes/native-main-environment.tres"
	if RenderingServer.get_rendering_device() == null:
		print("Renderer: Compatibility")
		# Compatibility/GLES3 has no RenderingDevice (that's Forward+/Mobile-Vulkan only)
		env_path = "res://scenes/compat-main-environment.tres"
		$WorldEnvironment.environment = load(env_path)
		
