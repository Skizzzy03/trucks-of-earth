import { lua, useBridge } from "@/bridge"

// Trucks of Earth (Trucks of Earth): its button in the main menu's "More" view (MainMenuButtons), the setup
// and office screens as routes of their own (ui/ui-vue/mods/README.md "Standalone routes"), and a card in the
// pause menu's shared Mods tab. Lua side: lua/ge/extensions/fernfahrer/career.lua.
const SOURCE = "fernfahrer.routes"
const MOD_ROOT = "/ui/ui-vue/mods/fernfahrer"
const PAUSE_BUTTON = "fernfahrer-office"

const { events } = useBridge()

function addMenuButton(addButton) {
  addButton({
    title: "Trucks of Earth",
    iconId: "semiTruckCabover",
    action: "fernfahrerCareers",        // the career picker (a route of its own)
  })
}

function routes(Setup, Office, Careers, Travel, Stop, Report) {
  return [
    {
      path: "/fernfahrer-report",
      name: "fernfahrerReport",
      component: Report,
      meta: { luaRoute: { title: "Lieferung", backTarget: "play" } },
    },
    {
      path: "/fernfahrer-stop",
      name: "fernfahrerStop",
      component: Stop,
      meta: { luaRoute: { title: "Haltepunkt", backTarget: "play" } },
    },
    {
      path: "/fernfahrer-travel",
      name: "fernfahrerTravel",
      component: Travel,
      meta: { luaRoute: { title: "Reise", backTarget: "play" } },
    },
    {
      path: "/fernfahrer-careers",
      name: "fernfahrerCareers",
      component: Careers,
      meta: { luaRoute: { title: "Trucks of Earth", backTarget: "menu" } },
    },
    {
      path: "/fernfahrer-setup",
      name: "fernfahrerSetup",
      component: Setup,
      meta: { luaRoute: { title: "Trucks of Earth", backTarget: "play" } },
    },
    {
      path: "/fernfahrer-office",
      name: "fernfahrerOffice",
      component: Office,
      meta: { luaRoute: { title: "Büro", backTarget: "play" } },
    },
  ]
}
const toLuaRoutes = records => records.map(r => ({ name: r.name, path: r.path, meta: r.meta }))

async function registerRoutes() {
  try {
    if (!window.bngRoutes || !lua.extensions.ui_router_routeManager) return
    const list = routes((await import("./FernfahrerSetup.vue")).default, (await import("./FernfahrerOffice.vue")).default,
                        (await import("./FernfahrerCareers.vue")).default, (await import("./FernfahrerTravel.vue")).default,
                        (await import("./FernfahrerStop.vue")).default, (await import("./FernfahrerReport.vue")).default)
    window.bngRoutes.add([{ path: SOURCE, routes: list }])
    const result = await lua.extensions.ui_router_routeManager.registerModRoutes(SOURCE, toLuaRoutes(list))
    if (!result?.success) {
      window.bngRoutes.remove([SOURCE])
      console.error("Fernfahrer: routes not registered", result?.errors)
    }
  } catch (e) {
    console.error("Fernfahrer: routes failed", e)
  }
}

export async function onLoad() {
  await registerRoutes()                           // first: the menu button navigates to one of them
  events.on("MainMenuButtons", addMenuButton)
  events.emit("BroadcastMainMenuButtons")          // a main menu already on screen asks again
  try {
    await lua.extensions.ui_pause_actions.registerModButton({
      id: PAUSE_BUTTON,
      tabId: "mods",
      label: "Trucks of Earth",
      icon: "semiTruckCabover",
      componentName: `${MOD_ROOT}/PauseCard.vue`,
    })
  } catch (e) {
    console.error("Fernfahrer: pause button failed", e)
  }
}

export async function onUnload() {
  events.off("MainMenuButtons", addMenuButton)
  try { await lua.extensions.ui_pause_actions.unregisterModButton(PAUSE_BUTTON) } catch (e) { /* not there */ }
  try {
    if (window.bngRoutes) window.bngRoutes.remove([SOURCE])
    if (lua.extensions.ui_router_routeManager) {
      await lua.extensions.ui_router_routeManager.unregisterModRoutes(SOURCE, { fallbackRoute: "play" })
    }
  } catch (e) {
    console.error("Fernfahrer: unload failed", e)
  }
}
