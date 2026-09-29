-- The name it had inside Quidquid, so a rebound key survives the move. Quidquid
-- dispatches by candidate type and input, so sharing its sequence with Quidquid's
-- temporary-request input is safe: that one never applies to resources.
data:extend({
  { type = "custom-input", name = "quidquid-pin-resource", key_sequence = "COMMAND + mouse-button-1" },
})
