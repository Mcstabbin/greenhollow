class_name Toonify
extends RefCounted
## Imported glTF models arrive with standard PBR shading. This flips their
## materials to Godot's built-in toon modes so everything in the world reads
## with the same flat, banded look as the hand-authored materials.
##
## Note this mutates the shared imported material resources, which is exactly
## what we want: every instance of a given model picks up the change.


static func apply(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var mat := mesh.surface_get_material(surface) as StandardMaterial3D
			if mat == null:
				continue
			# LAMBERT_WRAP, not TOON. Toon's hard two-band terminator collapses
			# every away-facing surface to flat ambient, which turned the whole
			# forest grey. Wrap bends light around the silhouette instead, which
			# is what foliage wants, and the outline shader already supplies the
			# "toon" read.
			mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			mat.roughness = 1.0
