local function action(name, fields)
  fields.contract_version = 4
  fields.types = { "resource" }
  return { type = "mod-data", name = "quidquid-resources-" .. name, data_type = "quidquid.action", data = fields }
end

-- Remote view and Factoriopedia reuse Quidquid's shared inputs and wording (EXTENDING.md
-- "Shared inputs"), so the player has one binding for each whatever the candidate type.
data:extend({
  action("remote-view", {
    label = { "quidquid.action-open-remote-view" },
    hint = { "quidquid.action-open-remote-view-hint" },
    input_name = "quidquid-open-remote-view",
    interface = "quidquid-resources.remote-view",
  }),
  action("factoriopedia", {
    label = { "quidquid.action-open-factoriopedia" },
    hint = { "quidquid.action-open-factoriopedia-hint" },
    input_name = "quidquid-open-factoriopedia",
    interface = "quidquid-resources.factoriopedia",
  }),
  action("pin", {
    label = { "quidquid-resources.action-pin-resource" },
    hint = { "quidquid-resources.action-pin-resource-hint" },
    input_name = "quidquid-pin-resource",
    interface = "quidquid-resources.pin",
  }),
})
