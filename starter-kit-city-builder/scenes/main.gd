extends Node3D

# ENSURE CONSISTENT LIGHTING BETWEEN RENDERERS

# Detect renderer and change
func _ready():
	
	# Debug output to verify renderer
	if RenderingServer.get_rendering_device():
		print("Renderer: Forward+")
	else:
		print("Renderer: Compatibility")
	
	var env_path := "res://scenes/native-main-environment.tres"
	if RenderingServer.get_rendering_device() == null:
		# Compatibility/GLES3 has no RenderingDevice (that's Forward+/Mobile-Vulkan only)
		env_path = "res://scenes/compat-main-environment.tres"
		$WorldEnvironment.environment = load(env_path)
		
