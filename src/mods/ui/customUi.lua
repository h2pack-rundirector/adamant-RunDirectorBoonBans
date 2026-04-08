local internal = RunDirectorBoonBans_Internal

public.definition.customTypes = {
    widgets = {
        rarityBadge = {
            binds = { value = { storageType = "int" } },
            slots = { "decrement", "value", "increment" },
            defaultGeometry = {
                slots = {
                    { name = "decrement", start = 0 },
                    { name = "value", start = 10, width = 100, align = "center" },
                    { name = "increment", start = 100 },
                },
            },
            validate = function(_, _) end,
            draw = function(ui, node, bound)
                local uiMod = internal.ui
                local current = bound.value:get() or 0
                if current < 0 then current = 0 end
                if current > 3 then current = 3 end
                local label = uiMod.RARITY_LABELS[current] or "Auto"
                local color = uiMod.RARITY_COLORS[current] or uiMod.RARITY_COLORS[0]
                local nextValue = current
                local slots = {
                    {
                        name = "decrement",
                        draw = function()
                            if ui.Button("-") and current > 0 then
                                nextValue = current - 1
                            end
                            return false
                        end,
                    },
                    {
                        name = "value",
                        sameLine = true,
                        draw = function(_, slot)
                            lib.alignSlotContent(ui, slot,
                                type(ui.CalcTextSize) == "function" and ui.CalcTextSize(label) or #(tostring(label)))
                            uiMod.DrawColoredText(ui, color, label)
                            return false
                        end,
                    },
                    {
                        name = "increment",
                        sameLine = true,
                        draw = function()
                            if ui.Button("+") and current < 3 then
                                nextValue = current + 1
                            end
                            return false
                        end,
                    },
                }
                lib.drawWidgetSlots(ui, node, slots)
                if nextValue ~= current then bound.value:set(nextValue) end
            end,
        }
    }
}
