# AutoRota — Talent Reference (Turtle WoW 1.18.1)

Authoritative talent-name dictionary, extracted in-game via `/ar talents`. These
are the exact `GetTalentInfo` strings for the 1.18.1 client. **Use these spellings
for any name-based talent detection** in the class modules.

> Live calculators for cross-checking: [Warrior](https://talents.turtlecraft.gg/warrior) ·
> [Paladin](https://talents.turtlecraft.gg/paladin) · [Hunter](https://talents.turtlecraft.gg/hunter) ·
> [Rogue](https://talents.turtlecraft.gg/rogue) · [Priest](https://talents.turtlecraft.gg/priest) ·
> [Shaman](https://talents.turtlecraft.gg/shaman) · [Mage](https://talents.turtlecraft.gg/mage) ·
> [Warlock](https://talents.turtlecraft.gg/warlock) · [Druid](https://talents.turtlecraft.gg/druid)

## Scope — what this dictionary does and does not verify

- ✅ **Talent names** (passive/active talents in the three trees per class). Authoritative.
- ⚠️ **Does NOT verify proc BUFF names.** A talent and the aura it grants often differ
  (e.g. the talent *Nightfall* grants the buff *Shadow Trance*; the talent *Elemental Focus*
  grants the buff *Clearcasting*). Buff names the rotations watch for must still be confirmed
  with `/ar debug` while the buff is active.
- ⚠️ **Does NOT list trained/baseline abilities.** Abilities learned from a trainer
  (e.g. *Mongoose Bite*, *Raptor Strike*, *Steady Shot*, *Blade Flurry*) are not talents and
  will not appear here; their exact names are confirmed via the spellbook / `/ar debug`.
- **Paladin is included below**, sourced from an earlier in-game talent dump (a `/run`
  macro printing tab + name). Its two name-based constants are confirmed present.

## Verification status of the strings AutoRota currently keys off

| Module | Constant / check | String | Status |
| :--- | :--- | :--- | :--- |
| Shaman | `TALENT_CLEARCAST` | `"Elemental Focus"` | ✅ confirmed in this dump (Elemental) |
| Warlock | `TALENT_NIGHTFALL` | `"Nightfall"` | ✅ confirmed in this dump (Affliction) |
| Warlock | `TALENT_RAPID_DETERIORATION` | `"Rapid Deterioration"` | ✅ confirmed in-game by a player: 2 ranks, 3% shorter Corruption/Curse of Agony/Siphon Life/Dark Harvest duration per rank (measured against the tooltip, not from an `/ar talents` dump) |
| Paladin | `TALENT_HOLY_MIGHT` | `"Vengeful Strikes"` | ✅ confirmed in Paladin dump (Retribution / tab 3) |
| Paladin | `TALENT_THREAT` | `"Righteous Strikes"` | ✅ confirmed in Paladin dump (Protection / tab 2) |

Talent-gated abilities detected via `KnowsSpell` were also cross-checked and all match:
*Carve, Lacerate, Kill Command* (Hunter); *Aimed Shot, Lock and Load* (Hunter MM);
*Noxious Assault, Envenom* (Rogue Assassination); *Riposte, Adrenaline Rush* (Rogue Combat);
*Death Wish* (Warrior Fury); *Sweeping Strikes* (Warrior Arms); *Bestial Wrath* (Hunter BM);
*Shadowburn* (Warlock Destruction); *Stormstrike, Bloodlust, Lightning Strike* (Shaman Enhancement);
*Elemental Mastery* (Shaman Elemental).

**Result: no code changes required — every name-based talent string in the modules is correct.**

Proc-buff names still pending an `/ar debug` confirm (almost certainly standard vanilla names,
but unproven by a talent dump): `Clearcasting` (Shaman, from Elemental Focus),
`Shadow Trance` (Warlock, from Nightfall), `Lock and Load` (Hunter buff aura).

---

## Hunter
- **Beast Mastery:** Swift Aspects, Endurance Training, Improved Eyes of the Beast, Improved Primal Aspects, Thick Hide, Improved Revive Pet, Pathfinding, Coordinated Assault, Unleashed Fury, Bestial Discipline, Improved Mend Pet, Ferocity, Scent of Blood, Bestial Wrath, Intimidation, Bestial Precision, Spirit Bond, Frenzy, Kill Command
- **Marksmanship:** Improved Concussive Shot, Efficiency, Improved Stings, Lethal Shots, Hawk Eye, Aimed Shot, Swiftshot, Endless Quiver, Mortal Shots, Scatter Shot, Experimental Ammunition, Piercing Shots, Barrage, Improved Marksmanship, Ranged Weapon Specialization, Lock and Load
- **Survival:** Improved Slaying, Resourcefulness, Swift Reflexes, Entrapment, Savage Strikes, Improved Wing Clip, Alone Against the World, Planning Ahead, Survivalist, Carve, Deterrence, Stinging Nettle, Surefooted, Improved Feign Death, Killer Instinct, Trap Mastery, Lacerate, Vicious Strikes, Lightning Reflexes, Untamed Trapper

## Rogue
- **Assassination:** Improved Eviscerate, Remorseless Attacks, Malice, Ruthlessness, Murder, Improved Blade Tactics, Relentless Strikes, Throwing Weapon Specialization, Lethality, Taste for Blood, Vile Poisons, Improved Poisons, Efficient Poisons, Envenom, Cold Blood, Vigor, Seal Fate, Noxious Assault
- **Combat:** Opportunity, Lightning Reflexes, Deflection, Improved Backstab, Precision, Riposte, Improved Sprint, Setup, Improved Kick, Concussive Blows, Dual Wield Specialization, Close Quarters Combat, Surprise Attack, Hack and Slash, Weapon Expertise, Blade Rush, Aggression, Adrenaline Rush
- **Subtlety:** Camouflage, Improved Expose Armor, Improved Gouge, Improved Ambush, Elusiveness, Serrated Blades, Initiative, Improved Ghostly Strike, Smoke Bomb, Hemorrhage, Cloaked in Shadows, Blackjack, Blinding Haze, Dirty Deeds, Preparation, Shadow of Death, Bloody Mess, Honor Among Thieves, Tricks of the Trade, Mark for Death

## Druid
- **Balance:** Improved Wrath, Nature's Grasp, Improved Nature's Grasp, Sylvan Blessing, Guidance of the Dream, Improved Moonfire, Natural Weapons, Natural Shapeshifter, Moonfury, Omen of Clarity, Nature's Reach, Vengeance, Moonglow, Owlkin Frenzy, Moonkin Form, Nature's Grace, Improved Starfire, Balance of All Things, Gale Winds, Eclipse
- **Feral Combat:** Ferocity, Feral Aggression, Feral Instinct, Brutal Impact, Thick Hide, Open Wounds, Feral Swiftness, Feral Charge, Sharpened Claws, Primal Fury, Predatory Strikes, Blood Frenzy, Improved Shred, Ancient Brutality, Berserk, Heart of the Wild, Carnage, Leader of the Pack
- **Restoration:** Improved Mark of the Wild, Furor, Improved Healing Touch, Nature's Focus, Subtlety, Swiftmend, Genesis, Reflection, Gift of Nature, Tranquil Spirit, Aessina's Bloom, Nature's Swiftness, Preservation, Improved Regrowth, Improved Tranquility, Tree of Life Form

## Warrior
- **Arms:** Improved Heroic Strike, Tactical Mastery, Improved Rend, Improved Charge, Deflection, Improved Thunder Clap, Master Strike, Improved Overpower, Deep Wounds, Two-Handed Weapon Specialization, Impale, Master of Arms, Sweeping Strikes, Boundless Anger, Improved Disciplines, Improved Slam, Precision Cut, Mortal Strike
- **Fury:** Booming Voice, Cruelty, Dual Wield Specialization, Unbridled Wrath, Improved Shouts, Piercing Howl, Blood Craze, Battlefield Mobility, Enrage, Improved Pummel, Ravager, Death Wish, Improved Execute, Improved Berserker Rage, Flurry, Blood Drinker, Bloodthirst
- **Protection:** Improved Bloodrage, Shield Specialization, Anticipation, Iron Will, Toughness, Last Stand, Improved Intervene, Improved Taunt, Improved Revenge, Gag Order, Improved Disarm, Defiance, One-Handed Weapon Specialization, Shield Slam, Improved Shield Slam, Reprisal, Improved Shield Wall, Defensive Tactics, Concussion Blow

## Warlock
- **Affliction:** Suppression, Improved Corruption, Improved Curse of Weakness, Resilient Shadows, Improved Life Tap, Improved Drains, Improved Curse of Agony, Fel Concentration, Curse of Exhaustion, Grim Reach, Nightfall, Soul Siphon, Rapid Deterioration, Siphon Life, Improved Curse of Exhaustion, Malediction, Shadow Mastery, Dark Harvest
- **Demonology:** Sinister Pursuit, Demonic Embrace, Soul Entrapment, Soul Funnel, Demonic Aegis, Fel Intellect, Fel Domination, Fel Stamina, Demonic Sacrifice, Improved Stones, Master Summoner, Nether Studies, Unholy Power, Power Overwhelming, Demonic Precision, Master Demonologist, Unleashed Potential, Soul Link
- **Destruction:** Shadow Vulnerability, Cataclysm, Demonic Swiftness, Bane, Aftermath, Intensity, Shadowburn, Devastation, Pyroclasm, Destructive Reach, Improved Searing Pain, Improved Soul Fire, Improved Immolate, Ruin, Emberstorm, Conflagrate

## Shaman
- **Elemental:** Convection, Concussion, Earth's Grasp, Elemental Warding, Elemental Devastation, Elemental Focus, Reverberation, Call of Thunder, Improved Molten Blast, Improved Fire Totems, Call of Earth, Call of Flame, Storm Reach, Elemental Mastery, Elemental Fury, Lightning Mastery, Earthquake
- **Enhancement:** Ancestral Knowledge, Shield Specialization, Totemic Alignment, Thundering Strikes, Stable Shields, Improved Ghost Wolf, Calming Winds, Lightning Strike, Ancestral Guardian, Flurry, Spirit Armor, Enhancing Totems, Elemental Weapons, Stormstrike, Element's Grace, Bloodlust
- **Restoration:** Improved Healing Wave, Tidal Focus, Improved Reincarnation, Ancestral Healing, Tidal Mastery, Healing Way, Healing Focus, Totemic Mastery, Nature's Grace, Restorative Totems, Improved Water Shield, Tidal Surge, Ancestral Swiftness, Undertow, Improved Chain Heal, Spirit Link

## Priest
- **Discipline:** Wand Specialization, Piercing Light, Mental Agility, Silent Resolve, Unbreakable Will, Blessed Concentration, Improved Power Word: Fortitude, Improved Inner Fire, Inner Focus, Improved Power Word: Shield, Meditation, Searing Light, Purifying Flames, Mental Strength, Enlighten, Resurgent Shield, Force of Will, Chastise
- **Holy:** Improved Renew, Holy Focus, Divinity, Divine Fury, Spell Warding, Holy Reach, Blessed Recovery, Inspiration, Holy Nova, Empowered Recovery, Improved Healing, Spiritual Guidance, Book of Prayer, Spirit of Redemption, Reservoir of Light, Spiritual Healing, Ascendance
- **Shadow:** Spirit Tap, Improved Mind Blast, Shadow Affinity, Improved Shadow Word: Pain, Shadow Focus, Blackout, Improved Psychic Scream, Improved Fade, Mind Flay, Improved Mana Burn, Shadow Reach, Shadow Weaving, Silence, Vampiric Embrace, Vampiric Touch, Darkness, Shadowform

## Mage
- **Arcane:** Arcane Subtlety, Magic Absorption, Improved Arcane Missiles, Wand Specialization, Arcane Focus, Arcane Concentration, Magic Attunement, Arcane Impact, Arcane Rupture, Improved Mana Shield, Improved Counterspell, Temporal Convergence, Arcane Meditation, Arcane Instability, Presence of Mind, Accelerated Arcana, Arcane Potency, Resonance Cascade, Arcane Power
- **Fire:** Improved Fireball, Impact, Ignite, Flame Throwing, Improved Fire Blast, Incinerate, Improved Flamestrike, Pyroblast, Burning Soul, Fire Vulnerability, Improved Fire Ward, Master of Elements, Blast Wave, Critical Mass, Hot Streak, Fire Power, Combustion
- **Frost:** Frost Warding, Improved Frostbolt, Elemental Precision, Piercing Ice, Frostbite, Improved Frost Nova, Permafrost, Ice Shards, Cold Snap, Improved Blizzard, Arctic Reach, Frost Channeling, Shatter, Ice Block, Icicles, Improved Cone of Cold, Winter's Chill, Flash Freeze, Ice Barrier

## Paladin
Source: your earlier in-game `/run … GetTalentInfo` dump (tab 1 = Holy, tab 2 = Protection, tab 3 = Retribution). Authoritative for the live client — note this dump shows the Retribution talent as **Vengeful Strikes**, *not* the wiki's "Crusading Strikes", which is exactly why the code keys off this string.
- **Holy:** Divine Intellect, Holy Judgement, Spiritual Focus, Improved Seal of Righteousness, Healing Light, Sanctity Aura, Improved Lay on Hands, Unyielding Faith, Improved Concentration Aura, Illumination, Ironclad, Divine Favor, Holy Shock, Holy Power, Blessed Strikes, Daybreak
- **Protection:** Improved Devotion Aura, Redoubt, Precision, Guardian's Favor, Toughness, Improved Righteous Fury, Blessing of Sanctuary, Shield Specialization, Anticipation, Improved Hand of Reckoning, Improved Hammer of Justice, Righteous Defense, Holy Shield, Reckoning, Righteous Strikes, Bulwark of the Righteous
- **Retribution:** Improved Blessings, Benediction, Improved Judgement, Improved Seal of the Crusader, Deflection, Improved Retribution Aura, Conviction, Blessing of Kings, Pursuit of Justice, Two-Handed Weapon Specialization, Vindication, Eye for an Eye, Vengeance, Seal of Command, Vengeful Strikes, Repentance

---

> **Note:** The Paladin dump above came from a `/run` macro that prints tab + name only,
> so it lists the talent names without per-tree section headers from `/ar talents`.
> The tab→spec mapping (1 Holy, 2 Protection, 3 Retribution) is the standard Paladin order.
> The two name-based constants are confirmed present: `"Vengeful Strikes"` (Retribution)
> and `"Righteous Strikes"` (Protection).

