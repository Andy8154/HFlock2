-- Widgets shared by the admin menu and the skill check windows.
-- Every widget is a normal Derma panel with its own Paint.

local Theme = HeistFlock.Theme
local S = HeistFlock.S
local UI = {}
HeistFlock.UI = UI

local function playClick()
	surface.PlaySound("ui/buttonclick.wav")
end

-- Eases a 0-1 hover value on the panel; call from Paint.
local function hoverAmount(panel, isOn)
	panel.HoverAmount = Lerp(math.min(FrameTime() * 14, 1), panel.HoverAmount or 0, isOn and 1 or 0)
	return panel.HoverAmount
end
UI.HoverAmount = hoverAmount

-- Tooltips -----------------------------------------------------------------
-- Drawn by us instead of Derma's default tooltip box.

local tooltipPanel, tooltipText

function UI.SetTooltip(panel, text)
	if not text or text == "" then return end

	local oldEnter, oldExit = panel.OnCursorEntered, panel.OnCursorExited
	panel.OnCursorEntered = function(self, ...)
		tooltipPanel, tooltipText = self, text
		if oldEnter then oldEnter(self, ...) end
	end
	panel.OnCursorExited = function(self, ...)
		if tooltipPanel == self then tooltipPanel = nil end
		if oldExit then oldExit(self, ...) end
	end
end

hook.Add("DrawOverlay", "HeistFlock_Tooltip", function()
	if not IsValid(tooltipPanel) or not tooltipPanel:IsHovered() or not tooltipPanel:IsVisible() then return end

	surface.SetFont("HeistFlock.Small")
	local textW, textH = surface.GetTextSize(tooltipText)
	local w, h = textW + S(20), textH + S(14)
	local x, y = gui.MouseX() + S(14), gui.MouseY() + S(18)
	x = math.min(x, ScrW() - w - S(8))

	HeistFlock.DrawBox(x, y, w, h, Theme.raised, Theme.line)
	draw.SimpleText(tooltipText, "HeistFlock.Small", x + S(10), y + h / 2, Theme.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end)

-- Scroll panels ------------------------------------------------------------

function UI.StyleScroll(scroll)
	local bar = scroll:GetVBar()
	bar:SetWide(S(6))
	bar:SetHideButtons(true)
	bar.Paint = function() end
	bar.btnGrip.Paint = function(self, w, h)
		local hover = hoverAmount(self, self:IsHovered() or self.Depressed)
		draw.RoundedBox(w / 2, 0, 0, w, h, HeistFlock.LerpColor(hover, Theme.line, Theme.textFaint))
	end
end

-- Buttons ------------------------------------------------------------------

local BUTTON_STYLES = {
	primary   = { fill = Theme.accent, hover = Color(110, 245, 196), text = Theme.accentText },
	secondary = { fill = Theme.raised, hover = Theme.hover, text = Theme.text, border = Theme.line },
	ghost     = { fill = Color(0, 0, 0, 0), hover = Theme.raised, text = Theme.textDim },
	danger    = { fill = Theme.raised, hover = Theme.redSoft, text = Theme.red, border = Theme.line },
}

-- options: style ("primary", "secondary", "ghost", "danger"), icon, tooltip
function UI.Button(parent, text, onClick, options)
	options = options or {}
	local colors = BUTTON_STYLES[options.style or "secondary"]

	surface.SetFont("HeistFlock.Body")
	local textWidth = surface.GetTextSize(text)
	local iconSize = S(16)

	local button = vgui.Create("DButton", parent)
	button:SetText("")
	button:SetSize(textWidth + S(28) + (options.icon and iconSize + S(8) or 0), S(34))

	button.Paint = function(self, w, h)
		local disabled = self:GetDisabled()
		local hover = hoverAmount(self, self:IsHovered() and not disabled)
		local fill = HeistFlock.LerpColor(hover, colors.fill, colors.hover)
		local textColor = disabled and Theme.textFaint or colors.text
		if disabled then fill = Theme.raised end

		HeistFlock.DrawBox(0, 0, w, h, fill, colors.border)

		local x = S(14)
		if options.icon then
			HeistFlock.DrawIcon(options.icon, x, (h - iconSize) / 2, iconSize, textColor)
			x = x + iconSize + S(8)
		end
		draw.SimpleText(text, "HeistFlock.Body", x, h / 2, textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	button.DoClick = function()
		playClick()
		onClick()
	end

	UI.SetTooltip(button, options.tooltip)
	return button
end

function UI.IconButton(parent, icon, tooltip, onClick, isDanger)
	local button = vgui.Create("DButton", parent)
	button:SetText("")
	button:SetSize(S(30), S(30))

	button.Paint = function(self, w, h)
		local hover = hoverAmount(self, self:IsHovered())
		if hover > 0.01 then
			draw.RoundedBox(S(4), 0, 0, w, h, ColorAlpha(isDanger and Theme.redSoft or Theme.hover, 255 * hover))
		end
		local color = HeistFlock.LerpColor(hover, Theme.textDim, isDanger and Theme.red or Theme.text)
		HeistFlock.DrawIcon(icon, (w - S(16)) / 2, (h - S(16)) / 2, S(16), color)
	end

	button.DoClick = function()
		playClick()
		onClick()
	end

	UI.SetTooltip(button, tooltip)
	return button
end

-- Inputs -------------------------------------------------------------------

function UI.Toggle(parent, value, onChange)
	local toggle = vgui.Create("DButton", parent)
	toggle:SetText("")
	toggle:SetSize(S(40), S(22))
	toggle.Value = value
	toggle.Knob = value and 1 or 0

	toggle.Paint = function(self, w, h)
		self.Knob = Lerp(math.min(FrameTime() * 16, 1), self.Knob, self.Value and 1 or 0)
		local track = HeistFlock.LerpColor(self.Knob, Theme.line, Theme.accent)
		draw.RoundedBox(h / 2, 0, 0, w, h, track)

		local knobSize = h - S(6)
		local knobX = S(3) + (w - knobSize - S(6)) * self.Knob
		draw.RoundedBox(knobSize / 2, knobX, S(3), knobSize, knobSize, self.Value and Theme.accentText or Theme.textDim)
	end

	toggle.DoClick = function(self)
		self.Value = not self.Value
		playClick()
		onChange(self.Value)
	end

	return toggle
end

function UI.TextBox(parent, width, value, numeric, unit, onChange)
	local box = vgui.Create("DPanel", parent)
	box:SetSize(width, S(32))

	local entry = vgui.Create("DTextEntry", box)
	entry:Dock(FILL)
	entry:DockMargin(S(10), 0, unit and S(48) or S(10), 0)
	entry:SetFont(numeric and "HeistFlock.Mono" or "HeistFlock.Body")
	entry:SetPaintBackground(false)
	entry:SetTextColor(Theme.text)
	entry:SetCursorColor(Theme.accent)
	entry:SetHighlightColor(ColorAlpha(Theme.accent, 80))
	entry:SetDrawLanguageID(false)
	entry:SetNumeric(numeric)
	entry:SetUpdateOnType(true)
	entry:SetValue(tostring(value))
	entry.OnValueChange = function(self, text) onChange(text) end
	box.Entry = entry

	box.Paint = function(self, w, h)
		local focus = hoverAmount(self, entry:HasFocus())
		HeistFlock.DrawBox(0, 0, w, h, Theme.input, HeistFlock.LerpColor(focus, Theme.line, Theme.accent))
		if unit then
			draw.SimpleText(unit, "HeistFlock.MonoSm", w - S(10), h / 2, Theme.textFaint, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end

	return box
end

function UI.Segmented(parent, choices, labels, value, onChange)
	local panel = vgui.Create("DPanel", parent)
	panel.Value = value
	panel:SetTall(S(32))
	panel.Paint = function(self, w, h)
		HeistFlock.DrawBox(0, 0, w, h, Theme.input, Theme.line)
	end

	local x = S(3)
	for i, choice in ipairs(choices) do
		surface.SetFont("HeistFlock.Small")
		local width = surface.GetTextSize(labels[i]) + S(24)

		local option = vgui.Create("DButton", panel)
		option:SetText("")
		option:SetPos(x, S(3))
		option:SetSize(width, S(26))
		option.Paint = function(self, w, h)
			local selected = panel.Value == choice
			local hover = hoverAmount(self, self:IsHovered() and not selected)
			if selected then
				draw.RoundedBox(S(3), 0, 0, w, h, Theme.raised)
			elseif hover > 0.01 then
				draw.RoundedBox(S(3), 0, 0, w, h, ColorAlpha(Theme.raised, 255 * hover))
			end
			draw.SimpleText(labels[i], "HeistFlock.Small", w / 2, h / 2, selected and Theme.text or Theme.textDim,
				TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			if selected then
				draw.RoundedBox(0, S(8), h - S(2), w - S(16), S(2), Theme.accent)
			end
		end
		option.DoClick = function()
			panel.Value = choice
			playClick()
			onChange(choice)
		end

		x = x + width + S(2)
	end

	panel:SetWide(x + S(1))
	return panel
end

-- A small "?" that explains something on hover.
function UI.Help(parent, text)
	local help = vgui.Create("DPanel", parent)
	help:SetSize(S(16), S(16))
	help:SetMouseInputEnabled(true)
	help.Paint = function(self, w, h)
		HeistFlock.DrawIcon("help", 0, 0, w, self:IsHovered() and Theme.text or Theme.textFaint)
	end
	UI.SetTooltip(help, text)
	return help
end

-- A status pill like "READY" or "BLOCKED".
function UI.DrawPill(text, x, y, color, alignRight)
	surface.SetFont("HeistFlock.Label")
	local textW, textH = surface.GetTextSize(text)
	local w, h = textW + S(14), textH + S(6)
	if alignRight then x = x - w end

	draw.RoundedBox(S(3), x, y - h / 2, w, h, ColorAlpha(color, 30))
	draw.SimpleText(text, "HeistFlock.Label", x + w / 2, y, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	return w
end
