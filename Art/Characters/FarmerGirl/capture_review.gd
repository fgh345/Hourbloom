extends SceneTree
## Run a copy outside Art/.gdignore with a real renderer, not --headless.
const OUTPUT = "res://Art/Characters/FarmerGirl/renders/"
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	root.size = Vector2i(640, 800)
	var review = load("res://Scenes/Tools/FarmerGirlReview.tscn").instantiate()
	root.add_child(review)
	await process_frame
	for child in review.get_children():
		if child is CanvasLayer:
			child.hide()
	review._appearance.set_process(false)
	review._animator.play("Idle")
	review._animator.pause()
	review._animator.seek(0.0, true)
	review._set_angle(0.0)
	await settle()
	var first: Image = await snapshot()
	first.save_png(OUTPUT + "game_front.png")
	var sheet := Image.create_empty(1920, 1200, false, Image.FORMAT_RGB8)
	var eye_images: Array[Image] = []
	for index in review.EXPRESSIONS.size():
		var expression = review.EXPRESSIONS[index]
		review._appearance.set_expression(expression)
		await settle()
		var shot: Image = await snapshot()
		shot.save_png(OUTPUT + "game_expression_" + String(expression).to_lower() + ".png")
		var face := shot.get_region(Rect2i(220, 210, 200, 160))
		eye_images.append(face)
		shot.resize(480, 600, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(shot, Rect2i(0, 0, 480, 600), Vector2i((index % 4) * 480, int(index / 4) * 600))
	sheet.save_png(OUTPUT + "expression_sheet.png")
	for index in range(1, eye_images.size()):
		print("EXPRESSION_PIXELS ", review.EXPRESSIONS[index], " differs=", eye_images[0].get_data() != eye_images[index].get_data())
	review._appearance.set_expression(&"Neutral")
	review._set_angle(PI / 4.0)
	for clip in ["Watering", "Carry"]:
		review._select_animation(review.ANIMATIONS.find(clip))
		review._animator.play(clip, 0.0)
		review._animator.seek(0.4, true)
		review._animator.advance(0.0)
		review._animator.pause()
		await settle()
		(await snapshot()).save_png(OUTPUT + "game_" + clip.to_lower() + ".png")
	review.queue_free()
	await process_frame
	print("GAME_REVIEW_CAPTURE_OK")
	quit()
func settle() -> void:
	for frame in 32:
		await process_frame
func snapshot() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
