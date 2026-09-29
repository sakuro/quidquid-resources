data:extend({
  {
    type = "mod-data",
    name = "quidquid-resources",
    data_type = "quidquid.source",
    order = "g",
    data = {
      contract_version = 3,
      type = "resource",
      label = { "quidquid-resources.source-resources" },
      -- "R" is uppercase because Quidquid's recipes hold "r"; prefixes are case-sensitive.
      prefixes = { "resource", "R" },
      in_default_search = false,
      interface = "quidquid-resources.source",
    },
  },
})
