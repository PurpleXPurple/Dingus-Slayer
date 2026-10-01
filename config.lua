local Cfg = {}

Cfg.AtkRange = 8
Cfg.HoverHeight = 20
Cfg.AtkIntMin = 0.35
Cfg.AtkIntMax = 0.75
Cfg.AtkIntBase = 0.55
Cfg.StunAtkInt = 0.28
Cfg.ScanTTL = 1.2
Cfg.HoverTTL = 0.05
Cfg.FaceTTL = 0.08
Cfg.RetreatHP = 0.35
Cfg.HoverP = 4000
Cfg.HoverD = 700
Cfg.MaxMoveTick = 8
Cfg.HitWindow = 12
Cfg.PullRange = 45
Cfg.MaxPull = 12
Cfg.UGDepth = 22
Cfg.UGTrigHP = 0.55
Cfg.UGMaxT = 6
Cfg.UGClearT = 1.6
Cfg.CrowCheckT = 1.5

Cfg.BossList = {
    "zuko","mother bear","honyozu","hoyuzo","yahaba","susamaru",
    "reaper","slasher","daki","gyutaro","douma","akaza","nezuko",
    "obanai","zentaro","sanemi","giyu","shiron","sabito","muichiro",
    "inosuke","rengoku","renpeke","swampy","yeti","tengen","tengai",
    "fujiko","enmu","shinobu","gyomei","kaiden","kaden","zanegutsu",
    "sumari","gyutai","gyorei","giyen","saneri","obari","nezura",
    "ren","rangu","ren trainee","trainee",
}

Cfg.WeaponList = {
    "sword","katana","cutlass","sickles","sickle","scythe","spear","tanto",
    "war fans","shotgun","gun","gauntlet","claw","claws","wagasa",
    "axe","mace","cleaver","saber","sabre","blade","rapier","nodachi",
    "wakizashi","tachi","nightfall","firstlight","damascus","enryu",
    "shinkage","tengoku","serpentine","tidal","tornadic","volcanic",
    "butterfly","thundercloud","scyther","blood","reaper slash",
}

Cfg.NoWeaponList = {
    "rod","fishing","horse","gourd","orb","potion","elixir","meat",
    "bandage","bell","scroll","pouch","map","ore","horn","silk","scrap",
    "ingot","cloth","plating","tentacle","worm","coral","shovel","permit",
    "letter","package","gemstone","note","schematic","lantern","chest",
    "coin","lure","fish","wen","voucher","crate","emote","mask","haori",
    "necklace","earring","crow","kasugai",
}

Cfg.SkillKeys = { "Z", "X", "C", "V", "B" }
Cfg.SkillCooldowns = { 1.2, 2.0, 2.8, 3.6, 6.0 }

Cfg.RotationOrder = { 2, 1, 3, 4, 5 }

Cfg.UI = {
    Font = Enum.Font.Gotham,
    FontBold = Enum.Font.GothamBold,
    FontCode = Enum.Font.Code,
    TextSize = 12,
    TextSizeSmall = 10,
    TextSizeTitle = 13,
    Bg = Color3.fromRGB(16, 16, 20),
    Bg2 = Color3.fromRGB(22, 22, 30),
    Bg3 = Color3.fromRGB(10, 10, 14),
    Border = Color3.fromRGB(60, 60, 75),
    Accent = Color3.fromRGB(200, 90, 70),
    AccentHover = Color3.fromRGB(230, 110, 90),
    Text = Color3.fromRGB(225, 225, 235),
    TextDim = Color3.fromRGB(160, 170, 190),
    Green = Color3.fromRGB(120, 220, 140),
    Red = Color3.fromRGB(240, 120, 120),
    Yellow = Color3.fromRGB(240, 200, 100),
    Blue = Color3.fromRGB(100, 180, 240),
    Purple = Color3.fromRGB(200, 140, 240),
    Cyan = Color3.fromRGB(100, 220, 220),
}

Cfg.CrowAsset = "rbxassetid://0"

return Cfg
