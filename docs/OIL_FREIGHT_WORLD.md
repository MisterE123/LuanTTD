# Oil wells, refinery, and town Goods

Choose **Oil and Refinery** in the new-world setup screen. No road, stop or vehicle
is prebuilt.

- Northfield Oil Wells: (11,2), exact five-cell stock layout. Start
  the crude route at the loading stop on (13,4).
- Westhaven Refinery: (15,17), exact fifteen-cell stock layout. Put
  one through truck stop at (16,16), just north of the receiving
  lanes. It accepts crude and is also the pickup for processed Goods.
- Mason Quay: the town Goods delivery stop at (14,8). It accepts
  original house Goods. Build the road depot at (11,12).

Build four linked road paths using these endpoints. Each arrow
denotes one road drag. The two approach loops give the truck physical
turnarounds without treating a through stop as a junction.

1. (12,4) → (16,4) → (16,7) → (15,7) → (15,8) → (12,8) →
   (12,14) → (14,14) → (14,16) → (18,16)
2. (12,4) → (12,5) → (16,5)
3. (15,8) → (15,12) → (12,12)
4. (18,16) → (18,15) → (14,15)

Use **Truck stop (3)** for the three stops and **Depot (4)** for the
garage. With Inspect selected, click your depot. Buy the original
**Witcombe Oil Tanker** for $6,015; it holds **21,000 L**. Order the
well stop and then the refinery. Buy the **Balogh Goods Truck** for
$5,851 and order the refinery and then the town. Start both from
Fleet. Delivering crude pays at the refinery. Each accepted unit of
crude produces one Goods crate; the Goods leg has its own fare.

The closed tanker uses the same correctly scaled 3D tank when empty
or loaded, like stock OpenTTD. Inspect the truck for its actual load,
or the facility and stops for production, receipts and acceptance.
The original pumping state and production are independent; the 3D
pumpjacks currently use the rig's fixed exported pose.

This is an authored land-oil scenario using stock machinery underneath.
No offshore oil rigs, water refits, player-funded processing layouts,
or general OpenTTD save interchange. See [source rules](OIL_INDUSTRY_PORT.md).
