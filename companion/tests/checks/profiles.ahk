; Remap profiles (2026-11-01): a new one copies the keys in use, switching swaps every slot's key and
; quickcast in and out, a save linked to a profile switches to it when loaded (applyProfile), a rename keeps
; the links, a delete unlinks them; the last profile can't be deleted. All in the checks' own ini.
TwcProfilesRun() {
    global remap, loader, iniFile
    for s in ["RemapProfiles", "LoadProfiles", "RemapProfile Default", "RemapProfile Hero", "RemapProfile Mage"]
        try IniDelete(iniFile, s)
    SetIni("$q", "Remap", "card9"), SetIni(1, "Remap", "cardQC9")
    p0 := remap.profile, l0 := remap.profiles().Length
    n1 := remap.newProfile("Hero")                                   ; a copy, in use
    SetIni("$z", "Remap", "card9"), SetIni(0, "Remap", "cardQC9")       ; Hero's own keys
    remap.useProfile("Default"), k1 := Ini("Remap", "card9", ""), q1 := Ini("Remap", "cardQC9", "")
    remap.useProfile("Hero"), k2 := Ini("Remap", "card9", ""), q2 := Ini("Remap", "cardQC9", "")
    TwcCheck(p0 = "Default" && l0 = 1 && n1 = "Hero" && k1 = "$q" && q1 = "1" && k2 = "$z" && q2 = "0",
        "profiles: Default at first; Hero a copy; switching swaps the keys (Default " k1 "/" q1 ", Hero " k2 "/" q2 ")")
    e1 := remap.newProfile("Mage", false), k3 := Ini("Remap", "card9", "-")
    dup := remap.newProfile("hero"), bad := remap.newProfile("  |  ")
    TwcCheck(e1 = "Mage" && k3 = "-" && remap.profile = "Mage" && dup = "" && bad = "", "an empty profile has no keys; a taken or empty name refused")
    ; a save linked to Hero: loading it switches (the load itself isn't run: applyProfile is its last step)
    loader.setProfileFor("knight#92.txt", "Hero")
    a1 := loader.applyProfile("knight#93.txt"), pr1 := remap.profile, a2 := loader.applyProfile("knight#93.txt")
    a3 := loader.applyProfile("other.txt"), pr3 := remap.profile
    TwcCheck(loader.profileFor("knight#91.txt") = "Hero" && a1 && pr1 = "Hero" && !a2 && !a3 && pr3 = "Hero",
        "a series linked to Hero: any of its saves switches to it; already in use: nothing; an unlinked save: the profile stays")
    r1 := remap.renameProfile("Hero", "Paladin"), lk := loader.profileFor("knight#92.txt")
    d1 := remap.deleteProfile("Paladin"), lk2 := loader.profileFor("knight#92.txt"), now := remap.profile
    d2 := remap.deleteProfile("Default"), d3 := remap.deleteProfile("Mage")
    TwcCheck(r1 = "Paladin" && lk = "Paladin" && d1 && lk2 = "" && now = "Default" && d2 && !d3 && remap.profiles().Length = 1,
        "rename keeps the link (" lk "); delete unlinks and the first other takes over (" now "); the last can't go")
    for s in ["RemapProfiles", "LoadProfiles", "RemapProfile Default", "RemapProfile Mage", "RemapProfile Paladin"]
        try IniDelete(iniFile, s)
    for k in ["card9", "cardQC9"]
        try IniDelete(iniFile, "Remap", k)
    remap.registerAll()
    TwcCheckDone()
}
SetTimer(TwcProfilesRun, -6000)
