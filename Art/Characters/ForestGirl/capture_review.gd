extends SceneTree
const OUTPUT = "res://Art/Characters/ForestGirl/Review/"
func _initialize(): call_deferred("capture")
func capture():
 root.size=Vector2i(720,900)
 var review=load("res://Scenes/Tools/FarmerGirlReview.tscn").instantiate()
 root.add_child(review)
 await process_frame
 for child in review.get_children():
  if child is CanvasLayer:child.hide()
 for angle in [0.0,PI/4.0,PI/2.0,PI]:
  review._set_angle(angle)
  review._animator.play("Idle",0.0);review._animator.seek(0.0,true);review._animator.advance(0.0);review._animator.pause()
  for frame in 32:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OUTPUT+"game_view_%d.png"%int(rad_to_deg(angle)))
 review._set_angle(PI/4.0)
 for clip in ["Walk","freehand_run","jump_start","jump_move","landing_soft","freehand_fall","fall_move","landing_recoil"]:
  review._animator.play(clip,0.0)
  var duration=review._animator.get_animation(clip).length
  review._animator.seek(duration*.4,true);review._animator.advance(0.0);review._animator.pause()
  for frame in 32:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(OUTPUT+"game_"+clip+".png")
 review.queue_free();await process_frame
 print("FOREST_GAME_CAPTURE_OK");quit()
