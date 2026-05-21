--!strict
-- Keeps the main UI windows exclusive: opening one menu closes the others.

type MenuRefs = {
	backdrop: Frame,
	root: Frame,
	show: (any) -> (),
}

local MenuController = {}
MenuController.__index = MenuController

export type Controller = typeof(setmetatable({} :: {
	menus: { [string]: MenuRefs },
	baseSizes: { [Frame]: UDim2 },
}, MenuController))

function MenuController.new(menus: { [string]: MenuRefs }): Controller
	local baseSizes: { [Frame]: UDim2 } = {}
	for _, refs in pairs(menus) do
		baseSizes[refs.root] = refs.root.Size
	end

	return setmetatable({
		menus = menus,
		baseSizes = baseSizes,
	}, MenuController)
end

function MenuController.closeAllMenus(self: Controller, exceptMenuName: string?)
	for menuName, refs in pairs(self.menus) do
		if menuName ~= exceptMenuName then
			refs.backdrop.Visible = false
			local baseSize = self.baseSizes[refs.root]
			if baseSize then
				refs.root.Size = baseSize
			end
		end
	end
end

function MenuController.openMenu(self: Controller, menuName: string)
	local refs = self.menus[menuName]
	if not refs then
		return
	end

	self:closeAllMenus(menuName)
	refs.show(refs)
end

function MenuController.toggleMenu(self: Controller, menuName: string)
	local refs = self.menus[menuName]
	if not refs then
		return
	end

	if refs.backdrop.Visible then
		refs.backdrop.Visible = false
		local baseSize = self.baseSizes[refs.root]
		if baseSize then
			refs.root.Size = baseSize
		end
		return
	end

	self:openMenu(menuName)
end

return MenuController
