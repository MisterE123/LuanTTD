"""Run inside the real Luanti client on a just-purchased passenger bus."""
import json


def exercise(harness, a, b, depot):
    get = harness["state"]
    wait = harness["await_state"]
    slot = harness["slot"]
    aim = harness["aim"]
    click = harness["click"]
    choose = harness["choose"]
    shot = harness["screenshot"]
    form = "luanttd_core:service"

    # Reopen from the depot using a right-click while Bulldoze is selected.
    # Before the fix that tool consumed ordinary world-click destinations.
    choose(form, "service_back", "order-modal-exit-first-bus-window")
    wait("bus form closed", lambda s: not s.get("form"))
    slot(9)
    aim(*depot)
    click(3)
    choose(form, "vehicle_1", "order-modal-reopen-bought-bus")
    choose(form, "service_pick", "order-modal-open-from-bulldoze")
    picking = wait("opening the real order hotbar from Bulldoze",
                   lambda s: s.get("menu") == "vehicle_orders" and not s.get("form")
                   and s.get("wield_item") == "luanttd_core:menu_order_pick")
    assert len(picking["hotbar_layout"]) == 2 and not picking.get("orders")

    # Mistaking the depot for a stop must not demolish it or change
    # the schedule. Capture the live error, then an eligible target.
    click()
    assert not get().get("orders") and get()["builds"] == picking["builds"]
    assert get()["cash"] == picking["cash"]
    shot("01-orders-invalid-depot")
    aim(*a)
    shot("02-orders-highlighted-bus-stop")
    click()
    one = wait("first world-clicked bus stop", lambda s: len(s.get("orders") or []) == 1)
    assert one["menu"] == "vehicle_orders"

    # The compact overlay has only the two order actions.
    slot(1)
    aim(*b)
    click()
    two = wait("second bus stop from the Pick tool", lambda s: len(s.get("orders") or []) == 2)
    assert two["orders"] == [1, 2] and two["builds"] == picking["builds"]
    shot("03-orders-two-saved-while-picking")
    slot(8)
    click()
    done = wait("Done reopens the bus orders and restores roadwork hotbar",
                lambda s: s.get("form") == form and s.get("menu") == "roads")
    assert done["orders"] == [1, 2] and len(done["hotbar_layout"]) > 2
    shot("04-orders-vehicle-window")

    # Re-enter from the low slot and verify Done is again kept out of the
    # automatically selected physical slot.
    choose(form, "service_pick", "order-modal-reopen")
    wait("mode entry always selects Pick, never Done",
         lambda s: s.get("menu") == "vehicle_orders" and s.get("wield_item") == "luanttd_core:menu_order_pick")
    click()  # the previous stop again, a deliberate duplicate rejection
    assert get()["menu"] == "vehicle_orders" and get()["orders"] == [1, 2]
    click(3)
    right_exit = wait("Right-click also returns with both saved orders",
                      lambda s: s.get("form") == form and s.get("menu") == "roads")
    assert right_exit["orders"] == [1, 2]
    choose(form, "service_toggle", "05-orders-start-service")
    running = wait("bus actually starts with the picked orders", lambda s: s["operating"])
    assert running["orders"] == [1, 2] and running["engine"] == "bus"
    harness["stop_server"](client_first=True)
    restored = harness["join"]("order-modal-restored")
    assert restored["orders"] == [1, 2]
    data = {"entry_slot": picking["hotbar"], "first_pick": one["orders"], "after_done": done["orders"],
            "after_right_click": right_exit["orders"], "running": running["operating"], "reopened": restored["orders"]}
    (harness["out"] / "bus-order-modal.json").write_text(json.dumps(data, indent=2))
    harness["stop_server"](client_first=True)
    print(f"PASS: new native bus picks orders despite prior Bulldoze with a compact order overlay, both finish methods, real service and restart: {harness['out']}")
