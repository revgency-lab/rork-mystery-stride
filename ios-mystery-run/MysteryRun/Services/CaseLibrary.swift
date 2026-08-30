//
//  CaseLibrary.swift
//  MysteryRun
//
//  Modular story components for the procedural case engine. Cases are assembled
//  from an archetype (the skeleton), a setting, a token cast, and a set of proof
//  beats — each beat becomes one physical clue on the route.
//

import Foundation

/// A physical evidence object a clue can take the shape of.
nonisolated struct EvidenceKind: Hashable, Sendable {
    let id: String
    let title: String
    let symbolName: String
}

/// One step of the proof. Rendered into a clue with a story fragment, a place it
/// was found, and the deduction it contributes to the resolution.
nonisolated struct ProofBeat: Sendable {
    let kinds: [String]
    let fragments: [String]
    let discoveries: [String]
    let deductions: [String]
    var isPivotal: Bool = false
    var isMisleading: Bool = false
}

/// The skeleton of a mystery: how it opens and how it resolves.
nonisolated struct CaseArchetype: Sendable {
    let id: String
    let titles: [String]
    let premises: [String]
    let beats: [ProofBeat]
    let conclusions: [String]
}

/// Physical flavour of the neighbourhood the case is set in.
nonisolated struct CaseSetting: Sendable {
    let id: String
    let name: String
    let photoAsset: String
    let spots: [String]
    let landmarks: [String]
}

enum CaseLibrary {
    // MARK: - Evidence catalogue

    static let evidence: [EvidenceKind] = [
        EvidenceKind(id: "note", title: "Torn Note", symbolName: "doc.plaintext.fill"),
        EvidenceKind(id: "key", title: "Brass Key", symbolName: "key.fill"),
        EvidenceKind(id: "phone", title: "Cracked Phone", symbolName: "iphone.gen3"),
        EvidenceKind(id: "footprint", title: "Boot Print", symbolName: "shoeprints.fill"),
        EvidenceKind(id: "stain", title: "Dried Stain", symbolName: "drop.fill"),
        EvidenceKind(id: "matchbook", title: "Matchbook", symbolName: "flame.fill"),
        EvidenceKind(id: "ticket", title: "Ticket Stub", symbolName: "ticket.fill"),
        EvidenceKind(id: "ledger", title: "Ledger Page", symbolName: "book.closed.fill"),
        EvidenceKind(id: "receipt", title: "Pawn Receipt", symbolName: "scroll.fill"),
        EvidenceKind(id: "glove", title: "Single Glove", symbolName: "hand.raised.fill"),
        EvidenceKind(id: "photo", title: "Bent Photograph", symbolName: "photo.fill"),
        EvidenceKind(id: "timetable", title: "Marked Timetable", symbolName: "clock.fill"),
        EvidenceKind(id: "makeup", title: "Theatre Makeup", symbolName: "paintpalette.fill"),
        EvidenceKind(id: "coin", title: "Foreign Coin", symbolName: "dollarsign.circle.fill"),
        EvidenceKind(id: "letter", title: "Sealed Letter", symbolName: "envelope.fill"),
        EvidenceKind(id: "badge", title: "Company Badge", symbolName: "shield.lefthalf.filled"),
        EvidenceKind(id: "lighter", title: "Engraved Lighter", symbolName: "lightbulb.fill"),
        EvidenceKind(id: "radio", title: "Radio Log", symbolName: "antenna.radiowaves.left.and.right"),
        EvidenceKind(id: "cargo", title: "Cargo Tag", symbolName: "shippingbox.fill"),
        EvidenceKind(id: "camera", title: "Exposed Film", symbolName: "camera.fill")
    ]

    static func evidenceKind(id: String) -> EvidenceKind {
        evidence.first { $0.id == id } ?? evidence[0]
    }

    // MARK: - Settings

    static let settings: [CaseSetting] = [
        CaseSetting(
            id: "harbor",
            name: "the harbor",
            photoAsset: "harbor_pier_night",
            spots: [
                "behind the ferry ticket booth on Pier 9",
                "wedged under a mooring cleat",
                "in the gutter outside the harbourmaster's office",
                "beneath a stack of pallets on the loading quay",
                "in a coil of rope at the end of the wharf",
                "caught in the grating by the fuel pumps",
                "on the deck of a half-loaded barge",
                "under the bench at the seaman's mission"
            ],
            landmarks: ["Pier 9", "the dry dock", "the fish market", "the customs shed", "the old lighthouse"]
        ),
        CaseSetting(
            id: "alley",
            name: "the back lanes",
            photoAsset: "alley_noir_night",
            spots: [
                "beside a dented service door",
                "on the third rung of a fire escape",
                "under a steaming vent grate",
                "behind the bins at the kitchen entrance",
                "tucked into a loose brick in the wall",
                "in a puddle beneath a broken bulb",
                "on the ledge above the delivery bay",
                "under a stack of flattened crates"
            ],
            landmarks: ["the Blue Room bar", "Kessler's laundry", "the printworks", "the night pharmacy", "the boxing gym"]
        ),
        CaseSetting(
            id: "station",
            name: "the station district",
            photoAsset: "railway_station_platform_night",
            spots: [
                "under a bench on platform four",
                "behind the departures board",
                "in the left-luggage cage",
                "jammed in the ticket machine's coin return",
                "on the rails just past the signal box",
                "in the waiting room's lost property tray",
                "beside the porters' trolley bay",
                "at the foot of the footbridge stairs"
            ],
            landmarks: ["platform four", "the signal box", "the parcel office", "the station hotel", "the tram terminus"]
        ),
        CaseSetting(
            id: "park",
            name: "the old park",
            photoAsset: "noir_park_bench",
            spots: [
                "under the bandstand steps",
                "in the hollow of a dead elm",
                "beside the frozen fountain",
                "on the gravel path near the east gate",
                "under a bench facing the pond",
                "caught in the railings by the rose garden",
                "beneath the keeper's hut window",
                "half buried in the flowerbed by the memorial"
            ],
            landmarks: ["the bandstand", "the east gate", "the boating pond", "the keeper's hut", "the war memorial"]
        )
    ]

    // MARK: - Token cast

    static let names = [
        "Alma Vester", "Tobias Crane", "Ruth Delacroix", "Emmett Hollis", "Nadia Quill",
        "Silas Renn", "Marguerite Oyelaran", "Viktor Brandt", "Corinne Ashby", "Idris Marlowe",
        "Petra Sandoval", "Callum Reyes", "Josephine Vane", "Hugo Lindqvist", "Mei-Lin Rowe",
        "Desmond Okafor", "Clara Bassett", "Nikolai Sørensen"
    ]

    static let roles = [
        "night courier", "ferry pilot", "dock clerk", "museum guard", "tram driver",
        "pawnbroker", "jazz pianist", "night nurse", "radio operator", "bookkeeper",
        "customs inspector", "theatre usher", "locksmith", "newspaper stringer", "cargo weighmaster"
    ]

    static let culprits = [
        "the harbourmaster", "her own business partner", "the night dispatcher", "a former colleague",
        "the building's caretaker", "the shipping agent", "an old creditor", "the assistant manager",
        "the man who reported it", "the company's own auditor", "the stage manager", "the desk sergeant's brother"
    ]

    static let items = [
        "a sealed cargo manifest", "the payroll satchel", "a jade cigarette case", "the Merrow diamond",
        "an unsigned will", "two crates of unlisted freight", "a set of forged passports",
        "the company's second ledger", "a violin case that never held a violin", "a bearer bond worth a year's wages",
        "a locked strongbox", "the missing shipping seal"
    ]

    static let motives = [
        "gambling debts nobody was supposed to know about",
        "an insurance payout on a boat that never sank",
        "a blackmail letter three years old",
        "a promotion that went to the wrong person",
        "money owed to people who don't send reminders",
        "a name on a document that shouldn't have been there",
        "a shipment the company insured twice",
        "a family debt inherited along with the business"
    ]

    static let vehicles = [
        "a grey delivery van", "the last tram", "a hired motorcycle", "an unmarked lorry",
        "the 11:40 ferry", "a black saloon car with taped-over plates"
    ]

    static let times = [
        "11:58 PM", "12:14 AM", "10:47 PM", "1:03 AM", "9:52 PM", "2:26 AM", "11:11 PM"
    ]

    // MARK: - Shared beats

    /// Corroborating beats used to pad longer routes.
    static let fillerBeats: [ProofBeat] = [
        ProofBeat(
            kinds: ["footprint", "glove", "coin"],
            fragments: [
                "A single print in the wet grit, size eleven, pressed deep like someone carrying weight.",
                "One glove, right hand, still damp. The stitching matches nothing sold in this district."
            ],
            discoveries: ["{spot}, twenty paces from {landmark}"],
            deductions: [
                "Whoever moved {item} was carrying it alone, and carrying it heavy.",
                "The same person came back a second time — the trail runs in both directions."
            ]
        ),
        ProofBeat(
            kinds: ["matchbook", "lighter", "ticket"],
            fragments: [
                "A matchbook from {landmark}. Inside the cover, a phone number half rubbed away.",
                "A ticket stub for {time}, torn in a hurry — the other half was never collected."
            ],
            discoveries: ["{spot}, near {landmark}"],
            deductions: [
                "It put someone at {landmark} on the same night, which nobody had admitted to.",
                "The stub proved the alibi was bought, not lived."
            ]
        ),
        ProofBeat(
            kinds: ["photo", "camera", "letter"],
            fragments: [
                "A bent photograph: two people shaking hands outside {landmark}. One face is scratched out.",
                "A letter, opened and refolded so many times the crease has gone soft."
            ],
            discoveries: ["{spot} in {place}"],
            deductions: [
                "The two of them knew each other long before anyone claimed they'd met.",
                "It showed the arrangement was old — this had been planned for months, not hours."
            ]
        ),
        ProofBeat(
            kinds: ["badge", "cargo", "radio"],
            fragments: [
                "A company badge, snapped clean off its pin, the number filed down.",
                "A cargo tag with the weight altered — the ink of the new figure is a shade too fresh."
            ],
            discoveries: ["{spot}, just out of the lamplight"],
            deductions: [
                "Someone with company access was in a place their pass didn't cover.",
                "The paperwork was doctored on site, not at the office."
            ]
        )
    ]

    /// Beats used for the misleading "unreliable narrator" variant.
    static let redHerringBeats: [ProofBeat] = [
        ProofBeat(
            kinds: ["stain", "glove", "footprint"],
            fragments: [
                "A dark stain across the stones, spreading toward the drain. It reads like the worst possible news.",
                "A torn coat sleeve with what looks unmistakably like blood along the cuff."
            ],
            discoveries: ["{spot}, where {place} meets the water"],
            deductions: [
                "This was meant to be found first — it isn't blood, and it was placed there to send the search the wrong way.",
                "The stain was staged. Every hour spent on it was an hour {culprit} needed."
            ],
            isMisleading: true
        ),
        ProofBeat(
            kinds: ["note", "letter"],
            fragments: [
                "A note in {name}'s handwriting: \"If you are reading this, I did not leave willingly.\"",
                "A hurried scrawl naming a stranger nobody in the district has ever heard of."
            ],
            discoveries: ["{spot}, folded far too neatly for a struggle"],
            deductions: [
                "The note was written days earlier and planted — the fold was clean, the ink was dry.",
                "The name in the note doesn't exist. It was invented to give the search a stranger to chase."
            ],
            isMisleading: true
        )
    ]

    // MARK: - Archetypes

    static let archetypes: [CaseArchetype] = [
        CaseArchetype(
            id: "staged_disappearance",
            titles: ["The Vanishing {roleTitle}", "The {roleTitle} Who Wasn't There", "Missing at {landmarkTitle}"],
            premises: [
                "{name}, a {role}, vanished near {place} last night. {clueCount} pieces of evidence are scattered along your route.",
                "A {role} walked into {place} at {time} and never walked out. Everything they left behind is still there — if you cover the ground."
            ],
            beats: [
                ProofBeat(
                    kinds: ["note", "letter"],
                    fragments: ["…meet me at {landmark} before midnight…"],
                    discoveries: ["{spot}"],
                    deductions: ["The note proved the {role} arranged a meeting at {landmark} that they never mentioned to anyone."]
                ),
                ProofBeat(
                    kinds: ["key", "receipt"],
                    fragments: ["A brass key, number 12, worn smooth from being carried in a pocket for weeks."],
                    discoveries: ["{spot}, under an inch of standing water"],
                    deductions: ["The key matched locker 12, where the {role}'s real belongings were already packed and waiting."],
                    isPivotal: true
                ),
                ProofBeat(
                    kinds: ["phone", "radio", "timetable"],
                    fragments: ["The screen still lights: last signal, {time}, one hundred metres from {landmark}."],
                    discoveries: ["{spot}, face down in the grit"],
                    deductions: ["The last signal placed the {role} at {landmark} at {time}, contradicting the statement they left behind."]
                ),
                ProofBeat(
                    kinds: ["makeup", "stain"],
                    fragments: ["A theatre makeup palette, the crimson worn down to the tin."],
                    discoveries: ["{spot}, wrapped in newspaper"],
                    deductions: ["The stain at the scene was staged with the same theatrical makeup found in that locker."]
                ),
                ProofBeat(
                    kinds: ["ticket", "cargo"],
                    fragments: ["A one-way ticket bought in cash, dated for the following morning."],
                    discoveries: ["{spot}, near {landmark}"],
                    deductions: ["The ticket showed the {role} intended to leave on their own terms, with {item} in hand."]
                ),
                ProofBeat(
                    kinds: ["ledger", "badge"],
                    fragments: ["A ledger page showing {item} signed out to a name that doesn't work here anymore."],
                    discoveries: ["{spot}, pinned under a brick"],
                    deductions: ["The paperwork tied the disappearance to {item} — the one thing that vanished with them."],
                    isPivotal: true
                )
            ],
            conclusions: [
                "THE {roleTitleUpper} STAGED THEIR OWN DISAPPEARANCE TO VANISH WITH {itemUpper}.",
                "NOBODY TOOK THE {roleTitleUpper}. THE {roleTitleUpper} TOOK {itemUpper} AND WALKED."
            ]
        ),
        CaseArchetype(
            id: "inside_job",
            titles: ["The {itemTitle} Job", "Nothing Was Forced", "The Quiet Theft at {landmarkTitle}"],
            premises: [
                "{item} went missing from {landmark} overnight, and not one lock was forced. {clueCount} clues sit along your route.",
                "Someone emptied {landmark} without breaking a thing. The trail runs through {place} — walk it and find out who had the keys."
            ],
            beats: [
                ProofBeat(
                    kinds: ["key", "badge"],
                    fragments: ["A key cut from a blank, still bright at the edges. Cut this week."],
                    discoveries: ["{spot}"],
                    deductions: ["The key was a fresh copy — someone with legitimate access made a duplicate days in advance."]
                ),
                ProofBeat(
                    kinds: ["timetable", "radio"],
                    fragments: ["A patrol timetable with the {time} round circled twice in pencil."],
                    discoveries: ["{spot}, folded to a quarter of its size"],
                    deductions: ["The circled round showed the theft was timed to the one gap in the night patrol."],
                    isPivotal: true
                ),
                ProofBeat(
                    kinds: ["ledger", "receipt"],
                    fragments: ["A ledger where the same weight is written twice, in two different hands."],
                    discoveries: ["{spot}, near {landmark}"],
                    deductions: ["The double entry proved {item} was written off the books before it ever left the building."]
                ),
                ProofBeat(
                    kinds: ["footprint", "glove"],
                    fragments: ["A print with no tread — soft-soled shoes, the kind worn indoors."],
                    discoveries: ["{spot}, in the dust by the service door"],
                    deductions: ["Whoever carried {item} out never came in from the street — they were already inside."]
                ),
                ProofBeat(
                    kinds: ["coin", "receipt"],
                    fragments: ["A pawn receipt for a wristwatch, redeemed in full three days later."],
                    discoveries: ["{spot}, damp and nearly illegible"],
                    deductions: ["Someone deep in debt on Monday had cash to spare by Thursday."]
                ),
                ProofBeat(
                    kinds: ["photo", "letter"],
                    fragments: ["A photograph of the night shift, one face circled in the same pencil as the timetable."],
                    discoveries: ["{spot}, under the boards"],
                    deductions: ["The circled face and the circled patrol round were drawn by the same hand — {culprit} planned both."],
                    isPivotal: true
                )
            ],
            conclusions: [
                "{culpritUpper} TOOK {itemUpper} FROM THE INSIDE AND LET THE STREET TAKE THE BLAME.",
                "THERE WAS NO BREAK-IN. {culpritUpper} SIMPLY UNLOCKED THE DOOR."
            ]
        ),
        CaseArchetype(
            id: "blackmail",
            titles: ["The Price of Silence", "Three Years of Letters", "What {landmarkTitle} Knew"],
            premises: [
                "{name} had been paying someone in cash for three years. Last night the payments stopped — violently. {clueCount} clues lie along your route.",
                "A {role} was being bled dry by somebody who knew too much. The evidence is scattered through {place}."
            ],
            beats: [
                ProofBeat(
                    kinds: ["letter", "note"],
                    fragments: ["\"The same as last month. Same place. Don't be clever.\" No signature, no stamp."],
                    discoveries: ["{spot}"],
                    deductions: ["The letter showed the {role} was being blackmailed, and had been for a long time."]
                ),
                ProofBeat(
                    kinds: ["ledger", "receipt"],
                    fragments: ["A withdrawal slip, the same amount, the same day of every month, for thirty-one months."],
                    discoveries: ["{spot}, in an envelope with no address"],
                    deductions: ["The payments were monthly and identical — this was a standing arrangement, not a robbery."],
                    isPivotal: true
                ),
                ProofBeat(
                    kinds: ["photo", "camera"],
                    fragments: ["A strip of exposed film. Held to the lamp: two figures at {landmark}, one handing over an envelope."],
                    discoveries: ["{spot}, near {landmark}"],
                    deductions: ["The film was the leverage itself — proof of {motive}."]
                ),
                ProofBeat(
                    kinds: ["matchbook", "lighter"],
                    fragments: ["An engraved lighter with initials that don't belong to the {role}."],
                    discoveries: ["{spot}, still warm to the touch"],
                    deductions: ["The initials matched the one person who was never supposed to be at {landmark} that night."]
                ),
                ProofBeat(
                    kinds: ["stain", "footprint"],
                    fragments: ["Scuffed gravel in a tight circle. Two people stood here and neither of them wanted to leave first."],
                    discoveries: ["{spot}, ten paces off the path"],
                    deductions: ["The scuffs showed the last handover turned into an argument."]
                ),
                ProofBeat(
                    kinds: ["key", "badge"],
                    fragments: ["A key to a room the {role} never rented, with the rent paid a year ahead."],
                    discoveries: ["{spot}, taped beneath the sill"],
                    deductions: ["The room was where the letters were written — and it was rented in {culprit}'s name."],
                    isPivotal: true
                )
            ],
            conclusions: [
                "{culpritUpper} HAD BEEN SELLING SILENCE FOR THREE YEARS — UNTIL THE PRICE WAS REFUSED.",
                "THE BLACKMAIL WAS THE MOTIVE, AND {culpritUpper} HELD THE PEN."
            ]
        ),
        CaseArchetype(
            id: "smuggling_chain",
            titles: ["The Drop Chain", "Freight That Doesn't Exist", "Six Stops to {landmarkTitle}"],
            premises: [
                "{item} moves through {place} every Thursday and never appears on any manifest. Your route is the chain. Find all {clueCount} drops.",
                "A {role} was moving cargo nobody insured. Walk the chain through {place} and see where it ends."
            ],
            beats: [
                ProofBeat(
                    kinds: ["cargo", "ledger"],
                    fragments: ["A cargo tag for a crate that was never weighed and never signed for."],
                    discoveries: ["{spot}"],
                    deductions: ["The tag proved cargo was moving through {place} outside the manifest entirely."]
                ),
                ProofBeat(
                    kinds: ["coin", "receipt"],
                    fragments: ["A foreign coin, worn thin, of a currency that doesn't trade at this port."],
                    discoveries: ["{spot}, kicked under the boards"],
                    deductions: ["The coin traced the freight back to a route that officially doesn't run here."]
                ),
                ProofBeat(
                    kinds: ["timetable", "radio"],
                    fragments: ["A radio log with a two-minute gap every Thursday, always at {time}."],
                    discoveries: ["{spot}, near {landmark}"],
                    deductions: ["Someone was switching the radio off at {time} every week — long enough for a handover."],
                    isPivotal: true
                ),
                ProofBeat(
                    kinds: ["footprint", "glove"],
                    fragments: ["Two sets of prints meeting and parting. Neither set walks back the way it came."],
                    discoveries: ["{spot}, in the mud beyond the lamps"],
                    deductions: ["Each drop had two people who never travelled together — a chain, not a crew."]
                ),
                ProofBeat(
                    kinds: ["matchbook", "ticket"],
                    fragments: ["A matchbook from {landmark} with six pencil marks inside the cover."],
                    discoveries: ["{spot}, dry despite the rain"],
                    deductions: ["Six marks for six drops — the chain was being counted off by hand."]
                ),
                ProofBeat(
                    kinds: ["badge", "note"],
                    fragments: ["A company badge belonging to the one person who signs off every manifest."],
                    discoveries: ["{spot}, snapped at the pin"],
                    deductions: ["The chain only worked because {culprit} signed the paperwork that made {item} disappear."],
                    isPivotal: true
                )
            ],
            conclusions: [
                "{culpritUpper} RAN THE CHAIN, AND {itemUpper} NEVER EXISTED ON PAPER AT ALL.",
                "THE FREIGHT WAS REAL. THE MANIFEST WAS THE LIE — AND {culpritUpper} WROTE IT."
            ]
        ),
        CaseArchetype(
            id: "mistaken_identity",
            titles: ["The Wrong Name", "Two Men, One Coat", "Who They Buried"],
            premises: [
                "Everyone agrees who was found near {landmark} last night. Everyone is wrong. {clueCount} clues along your route say so.",
                "A {role} was identified by their coat and nothing else. Walk {place} and find out who was actually wearing it."
            ],
            beats: [
                ProofBeat(
                    kinds: ["badge", "letter"],
                    fragments: ["A company badge in the coat's inner pocket. The number belongs to someone who resigned in spring."],
                    discoveries: ["{spot}"],
                    deductions: ["The badge in the coat belonged to a different person entirely."]
                ),
                ProofBeat(
                    kinds: ["footprint", "glove"],
                    fragments: ["A print two sizes smaller than the boots everyone described."],
                    discoveries: ["{spot}, preserved in setting concrete"],
                    deductions: ["The prints didn't fit the {role} — they fit somebody smaller and lighter."],
                    isPivotal: true
                ),
                ProofBeat(
                    kinds: ["photo", "camera"],
                    fragments: ["A photograph of two men outside {landmark}, near enough identical from behind."],
                    discoveries: ["{spot}, near {landmark}"],
                    deductions: ["From behind, in a coat, the two of them were impossible to tell apart."]
                ),
                ProofBeat(
                    kinds: ["ticket", "timetable"],
                    fragments: ["A ticket for {time} — the exact hour the {role} was supposedly already at {landmark}."],
                    discoveries: ["{spot}, soaked through"],
                    deductions: ["The {role} was still travelling at {time}. They could not have been at {landmark}."]
                ),
                ProofBeat(
                    kinds: ["key", "receipt"],
                    fragments: ["A key to a room rented under a name nobody recognises."],
                    discoveries: ["{spot}, hidden in a seam"],
                    deductions: ["The second name on the lease was the man actually wearing the coat."]
                ),
                ProofBeat(
                    kinds: ["letter", "ledger"],
                    fragments: ["A letter agreeing to \"swap for one night only — you know what for.\""],
                    discoveries: ["{spot}, burned at one corner"],
                    deductions: ["The swap was arranged in writing, and {culprit} needed it to hold for exactly one night."],
                    isPivotal: true
                )
            ],
            conclusions: [
                "THE MAN FOUND AT {landmarkTitleUpper} WAS NEVER THE {roleTitleUpper} — THE SWAP WAS THE WHOLE POINT.",
                "AN IDENTITY WAS BORROWED FOR ONE NIGHT SO {culpritUpper} COULD MOVE {itemUpper} UNSEEN."
            ]
        ),
        CaseArchetype(
            id: "sabotage",
            titles: ["The Fault That Wasn't", "Cut Twice", "Trouble at {landmarkTitle}"],
            premises: [
                "The failure at {landmark} was called an accident within the hour. Too fast. {clueCount} pieces of evidence say otherwise.",
                "A {role} was blamed for a fault at {landmark} at {time}. The proof they didn't cause it is scattered across {place}."
            ],
            beats: [
                ProofBeat(
                    kinds: ["cargo", "badge"],
                    fragments: ["A severed cable end, cut clean. Wear doesn't cut clean."],
                    discoveries: ["{spot}"],
                    deductions: ["The cut was made with a tool, not caused by wear — the failure was deliberate."],
                    isPivotal: true
                ),
                ProofBeat(
                    kinds: ["timetable", "radio"],
                    fragments: ["A maintenance sheet signed off at {time} for work that was never carried out."],
                    discoveries: ["{spot}, clipped to a nail"],
                    deductions: ["The paperwork was signed before the work — someone needed a reason to be alone there."]
                ),
                ProofBeat(
                    kinds: ["glove", "footprint"],
                    fragments: ["A work glove with the fingertips cut away, stiff with grease."],
                    discoveries: ["{spot}, near {landmark}"],
                    deductions: ["Whoever made the cut needed bare fingers — and knew exactly which line to reach for."]
                ),
                ProofBeat(
                    kinds: ["ledger", "receipt"],
                    fragments: ["An insurance schedule with the value raised, initialled two weeks ago."],
                    discoveries: ["{spot}, folded inside a newspaper"],
                    deductions: ["The cover was increased a fortnight before the failure. That timing isn't luck."]
                ),
                ProofBeat(
                    kinds: ["matchbook", "coin"],
                    fragments: ["A matchbook from {landmark}, with a shift number written inside."],
                    discoveries: ["{spot}, in the gutter"],
                    deductions: ["The shift number belonged to the only person on site at {time}."]
                ),
                ProofBeat(
                    kinds: ["note", "letter"],
                    fragments: ["A note: \"After it goes, act surprised. Then take the contract.\""],
                    discoveries: ["{spot}, torn in half and only half hidden"],
                    deductions: ["The note put {culprit} at the centre of it, working for {motive}."],
                    isPivotal: true
                )
            ],
            conclusions: [
                "IT WAS NEVER A FAULT. {culpritUpper} CUT THE LINE TO COLLECT ON IT.",
                "THE {roleTitleUpper} WAS BLAMED FOR SABOTAGE ARRANGED BY {culpritUpper}."
            ]
        ),
        CaseArchetype(
            id: "forged_will",
            titles: ["The Late Signature", "Ink Too Fresh", "An Heir Nobody Met"],
            premises: [
                "{item} surfaced two days after the funeral, signed and witnessed. The witnesses can't be found. {clueCount} clues wait along your route.",
                "A {role} left everything to a stranger. The proof it was forged is scattered through {place}."
            ],
            beats: [
                ProofBeat(
                    kinds: ["letter", "ledger"],
                    fragments: ["A signature practised eleven times down the margin, each one closer than the last."],
                    discoveries: ["{spot}"],
                    deductions: ["The signature on {item} was practised — somebody learned to write it."],
                    isPivotal: true
                ),
                ProofBeat(
                    kinds: ["receipt", "coin"],
                    fragments: ["A stationer's receipt for aged paper and iron-gall ink, dated after the funeral."],
                    discoveries: ["{spot}, near {landmark}"],
                    deductions: ["The materials were bought after the death — the document was made, not found."]
                ),
                ProofBeat(
                    kinds: ["photo", "camera"],
                    fragments: ["A photograph of the supposed witnesses, taken at {landmark} on a date they claim they were abroad."],
                    discoveries: ["{spot}, under glass"],
                    deductions: ["The witnesses were in the district all along, and were paid to say otherwise."]
                ),
                ProofBeat(
                    kinds: ["key", "badge"],
                    fragments: ["A safe key that opens a box already emptied."],
                    discoveries: ["{spot}, on a length of string"],
                    deductions: ["The real papers were removed from the box before anyone thought to look."]
                ),
                ProofBeat(
                    kinds: ["timetable", "ticket"],
                    fragments: ["A travel ticket for {time}, purchased in the name of the mystery heir."],
                    discoveries: ["{spot}, half burned"],
                    deductions: ["The heir was never a stranger — they were in {place} the whole week."]
                ),
                ProofBeat(
                    kinds: ["note", "lighter"],
                    fragments: ["A note listing what each person gets, in the same hand as the practised signature."],
                    discoveries: ["{spot}, weighted with a stone"],
                    deductions: ["The division was agreed in advance, and {culprit} wrote the list."],
                    isPivotal: true
                )
            ],
            conclusions: [
                "{itemUpper} WAS FORGED, AND {culpritUpper} WROTE EVERY WORD OF IT.",
                "THERE WAS NO HEIR. {culpritUpper} INVENTED ONE AND SIGNED FOR THEM."
            ]
        ),
        CaseArchetype(
            id: "double_life",
            titles: ["Two Sets of Keys", "The Second Address", "Nights the {roleTitle} Kept"],
            premises: [
                "{name} kept two lives, two names and two sets of keys. One of them got them killed. {clueCount} clues line your route.",
                "A {role} had a second address in {place} that nobody in their life knew about. Walk it and find out why."
            ],
            beats: [
                ProofBeat(
                    kinds: ["key", "receipt"],
                    fragments: ["Two keys on one ring. One opens a home. The other opens something else."],
                    discoveries: ["{spot}"],
                    deductions: ["The second key proved the {role} kept a room nobody in their life knew about."]
                ),
                ProofBeat(
                    kinds: ["letter", "note"],
                    fragments: ["A letter addressed to a name the {role} never used at work."],
                    discoveries: ["{spot}, near {landmark}"],
                    deductions: ["The second name was in daily use — this wasn't an escape plan, it was a routine."],
                    isPivotal: true
                ),
                ProofBeat(
                    kinds: ["ledger", "coin"],
                    fragments: ["A savings book in that second name, deposits far larger than a {role}'s wage."],
                    discoveries: ["{spot}, wrapped in oilcloth"],
                    deductions: ["The money coming in wasn't wages, which meant somebody else was paying."]
                ),
                ProofBeat(
                    kinds: ["photo", "camera"],
                    fragments: ["A photograph taken at {landmark}: the {role}, laughing, beside someone whose face is turned away."],
                    discoveries: ["{spot}, curled with damp"],
                    deductions: ["Someone shared the second life, and did not want to be photographed."]
                ),
                ProofBeat(
                    kinds: ["timetable", "ticket"],
                    fragments: ["A timetable with the {time} service circled every Tuesday for a year."],
                    discoveries: ["{spot}, under the mat"],
                    deductions: ["Every Tuesday at {time}, the {role} crossed {place} to become somebody else."]
                ),
                ProofBeat(
                    kinds: ["badge", "lighter"],
                    fragments: ["A company badge from a firm that competes with the {role}'s employer."],
                    discoveries: ["{spot}, pushed into a crack in the wall"],
                    deductions: ["The second life had an employer, and {culprit} was the one signing the cheques."],
                    isPivotal: true
                )
            ],
            conclusions: [
                "THE {roleTitleUpper} WAS PAID BY {culpritUpper} TO LIVE A SECOND LIFE — AND DIED WHEN THEY TRIED TO STOP.",
                "TWO LIVES, ONE PAYMASTER: {culpritUpper} OWNED THEM BOTH."
            ]
        )
    ]
}
