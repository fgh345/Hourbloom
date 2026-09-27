extends SceneTree
## godot --path . --resolution 1152x648 --fixed-fps 60 --write-movie /tmp/hoe_review.avi --script Scripts/debug/capture_hoe_review.gd
const Motion = preload("res://Assets/Tools/Hoe/HoeMotion.gd")
const OUTPUT := "res://Art/Tools/Hoe/Review/"

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(480, 600) if "--poses-only" in OS.get_cmdline_user_args() else Vector2i(1152, 648)
	var stage = load("res://Scenes/Tools/HoeReview.tscn").instantiate()
	stage.capture_mode = true
	root.add_child(stage)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	await process_frame
	if "--poses-only" in OS.get_cmdline_user_args():
		stage.set_view(.70)
		for control in stage.scrubber.get_parent().get_children():
			control.visible = control == stage.phase_label
		var times := [Motion.READY_TIME, Motion.RAISED_TIME, Motion.SWING_TIME, Motion.IMPACT_TIME, Motion.FOLLOW_TIME]
		for pose in times.size():
			stage.elapsed = times[pose]
			stage.particle_age = .05 if pose == 3 else 10.0
			stage.advance_preview(0.0)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT + "hoe_pose_%d.png" % (pose + 1))
		stage.queue_free()
		await process_frame
		print("HOE_POSES_CAPTURE_OK")
		quit()
		return
	if "--recovery-only" in OS.get_cmdline_user_args():
		stage.camera.size = 1.15
		var target := Vector3(0, .70, .10)
		stage.camera.position = target + Vector3(2.7, .8, 4.0)
		stage.camera.look_at(target)
		var cycle_frames := ceili((Motion.DURATION - Motion.IMPACT_TIME) * 120.0) + 25
		for frame in cycle_frames * 3:
			var time := Motion.IMPACT_TIME + minf((frame % cycle_frames) / 120.0, Motion.DURATION - Motion.IMPACT_TIME)
			stage.animator.seek(time, true)
			stage.scrubber.set_value_no_signal(time)
			stage.phase_label.text = "收锄 · 半速近景"
			await process_frame
			await RenderingServer.frame_post_draw
			if frame == roundi((Motion.FOLLOW_TIME - Motion.IMPACT_TIME) * 120):
				root.get_texture().get_image().save_png(OUTPUT + "hoe_recovery.png")
		stage.queue_free()
		await process_frame
		print("HOE_RECOVERY_CAPTURE_OK")
		quit()
		return
	if "--arms-only" in OS.get_cmdline_user_args():
		stage.animator.seek(Motion.RAISED_TIME, true)
		stage.camera.size = 1.05
		var target := Vector3(0, .77, .035)
		stage.camera.position = target + Vector3(2.7, .8, 4.0)
		stage.camera.look_at(target)
		stage.phase_label.text = "手臂与袖口 · 连接近景"
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT + "hoe_arms.png")
		stage.queue_free()
		await process_frame
		quit()
		return
	stage.set_view(.70)
	var view_frames := roundi((Motion.DURATION + .45) * 120)
	var images := {0: "hoe_000.png", roundi(Motion.RAISED_TIME * 60) - 1: "hoe_024.png", roundi(Motion.IMPACT_TIME * 60) - 1: "hoe_037.png", view_frames + roundi(Motion.RAISED_TIME * 60) - 1: "hoe_230.png", view_frames + roundi(Motion.IMPACT_TIME * 60) - 1: "hoe_241.png"}
	for frame in view_frames * 3:
		if frame == view_frames:
			stage.elapsed = 0
			stage.set_view(PI / 2)
		if frame == view_frames * 2:
			stage.elapsed = 0
			stage.set_view(0.0)
		stage.advance_preview(1.0 / 60.0)
		await process_frame
		await RenderingServer.frame_post_draw
		if images.has(frame):
			root.get_texture().get_image().save_png(OUTPUT + images[frame])
	stage.queue_free()
	await process_frame
	print("HOE_REVIEW_CAPTURE_OK")
	quit()
