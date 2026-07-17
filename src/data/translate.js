const WORD_MAP = {
  ko: {
    // Weapons
    'Sword':'검','Greatsword':'대검','Blade':'칼날','Dagger':'단검','Spear':'창',
    'Lance':'랜스','Bow':'활','Staff':'지팡이','Wand':'완드','Axe':'도끼',
    'Hammer':'망치','Mace':'철퇴','Scythe':'낫','Rifle':'소총','Gun':'총',
    'Cannon':'대포','Crossbow':'석궁','Katana':'카타나','Glaive':'글레이브',
    'Halberd':'미늘창','Rapier':'레이피어','Whip':'채찍','Claw':'발톱','Fist':'주먹',
    'Trident':'삼지창','Pike':'파이크',
    // Armor
    'Armor':'갑옷','Shield':'방패','Helm':'투구','Helmet':'투구','Crown':'왕관',
    'Circlet':'관','Robe':'로브','Cloak':'망토','Cape':'케이프','Vest':'조끼',
    'Plate':'판금','Mail':'사슬갑옷','Cuirass':'흉갑','Gauntlet':'건틀릿',
    'Boots':'부츠','Greaves':'경갑','Breastplate':'흉갑',
    // Accessories
    'Ring':'반지','Necklace':'목걸이','Amulet':'부적','Pendant':'펜던트',
    'Bracelet':'팔찌','Earring':'귀걸이','Belt':'벨트','Orb':'오브',
    'Signet':'인장','Talisman':'부적','Charm':'부적','Token':'토큰',
    'Wings':'날개','Halo':'후광','Feather':'깃털',
    // Materials
    'Fragment':'파편','Shard':'조각','Crystal':'수정','Gem':'보석','Stone':'돌',
    'Ore':'광석','Essence':'정수','Core':'핵','Dust':'가루','Powder':'분말',
    'Leaf':'잎','Branch':'가지','Root':'뿌리','Seed':'씨앗','Blossom':'꽃',
    'Petal':'꽃잎','Fruit':'열매','Berry':'열매','Herb':'약초',
    'Scale':'비늘','Fang':'이빨','Horn':'뿔','Bone':'뼈','Hide':'가죽',
    'Claw':'발톱','Eye':'눈','Heart':'심장','Blood':'피','Soul':'영혼',
    'Spirit':'정령','Tear':'눈물','Breath':'숨결',
    // Adjectives
    'Ancient':'고대의','Sacred':'신성한','Holy':'성스러운','Divine':'신성한',
    'Dark':'어둠의','Shadow':'그림자','Cursed':'저주받은','Unholy':'불경한',
    'Crimson':'핏빛','Golden':'황금','Silver':'은빛','Crystal':'수정',
    'Frozen':'얼어붙은','Burning':'불타는','Thunder':'천둥','Lightning':'번개',
    'Storm':'폭풍','Wind':'바람','Fire':'불','Ice':'얼음','Water':'물',
    'Earth':'대지','Light':'빛','Celestial':'천상의','Infernal':'지옥의',
    'Abyssal':'심연의','Void':'공허','Chaos':'혼돈','Arcane':'비전',
    'Mystic':'신비의','Ethereal':'공허한','Phantom':'환영','Spectral':'유령의',
    'Royal':'왕실의','Imperial':'황제의','Dragon':'용','Demon':'악마',
    'Angel':'천사','Phoenix':'불사조','Fallen':'타락한','Twisted':'뒤틀린',
    'True':'진정한','Ultimate':'궁극의','Supreme':'최고의','Grand':'위대한',
    'Great':'대','Mighty':'강력한','Eternal':'영원의','Immortal':'불멸의',
    'Legendary':'전설의','Mythic':'신화의','Epic':'서사시의',
    // Nouns
    'King':'왕','Queen':'여왕','Prince':'왕자','Knight':'기사','Warrior':'전사',
    'Mage':'마법사','Wizard':'마법사','Witch':'마녀','Priest':'사제',
    'Dragon':'용','Serpent':'뱀','Wolf':'늑대','Bear':'곰','Eagle':'독수리',
    'Raven':'까마귀','Spider':'거미','Scorpion':'전갈',
    'Tower':'탑','Castle':'성','Throne':'왕좌','Temple':'신전','Altar':'제단',
    'Tomb':'무덤','Ruins':'폐허','Abyss':'심연','Heaven':'천국','Hell':'지옥',
    'Forest':'숲','Mountain':'산','Ocean':'바다','River':'강','Desert':'사막',
    'Sun':'태양','Moon':'달','Star':'별','Sky':'하늘','Night':'밤',
    'Death':'죽음','Life':'생명','Time':'시간','Fate':'운명','War':'전쟁',
    'Peace':'평화','Truth':'진실','Wisdom':'지혜','Power':'힘','Glory':'영광',
    'Wrath':'분노','Fury':'격노','Rage':'격노','Doom':'파멸',
    // Prepositions/articles (for pattern matching)
    'of':'의','the':'','from':'에서 온','and':'과',
  },
  zh: {
    // Weapons
    'Sword':'剑','Greatsword':'大剑','Blade':'刃','Dagger':'匕首','Spear':'矛',
    'Lance':'长枪','Bow':'弓','Staff':'法杖','Wand':'魔杖','Axe':'斧',
    'Hammer':'锤','Mace':'钉锤','Scythe':'镰刀','Rifle':'步枪','Gun':'枪',
    'Cannon':'火炮','Crossbow':'弩','Katana':'太刀','Glaive':'关刀',
    'Halberd':'戟','Rapier':'细剑','Whip':'鞭','Claw':'爪','Fist':'拳',
    'Trident':'三叉戟','Pike':'长矛',
    // Armor
    'Armor':'铠甲','Shield':'盾','Helm':'头盔','Helmet':'头盔','Crown':'王冠',
    'Circlet':'头环','Robe':'法袍','Cloak':'斗篷','Cape':'披风','Vest':'背心',
    'Plate':'板甲','Mail':'锁甲','Cuirass':'胸甲','Gauntlet':'护手',
    'Boots':'靴子','Greaves':'胫甲','Breastplate':'胸甲',
    // Accessories
    'Ring':'戒指','Necklace':'项链','Amulet':'护符','Pendant':'吊坠',
    'Bracelet':'手镯','Earring':'耳环','Belt':'腰带','Orb':'宝珠',
    'Signet':'印章','Talisman':'符咒','Charm':'护符','Token':'令牌',
    'Wings':'之翼','Halo':'光环','Feather':'羽毛',
    // Materials
    'Fragment':'碎片','Shard':'裂片','Crystal':'水晶','Gem':'宝石','Stone':'石',
    'Ore':'矿石','Essence':'精华','Core':'核心','Dust':'尘','Powder':'粉末',
    'Leaf':'叶','Branch':'枝','Root':'根','Seed':'种子','Blossom':'花',
    'Petal':'花瓣','Fruit':'果实','Berry':'浆果','Herb':'药草',
    'Scale':'鳞片','Fang':'獠牙','Horn':'角','Bone':'骨','Hide':'兽皮',
    'Claw':'爪','Eye':'之眼','Heart':'之心','Blood':'血','Soul':'魂',
    'Spirit':'灵','Tear':'之泪','Breath':'吐息',
    // Adjectives
    'Ancient':'远古','Sacred':'神圣','Holy':'圣','Divine':'神圣',
    'Dark':'暗黑','Shadow':'暗影','Cursed':'诅咒','Unholy':'亵渎',
    'Crimson':'赤红','Golden':'黄金','Silver':'白银','Crystal':'水晶',
    'Frozen':'冰封','Burning':'燃烧','Thunder':'雷霆','Lightning':'闪电',
    'Storm':'风暴','Wind':'风','Fire':'火','Ice':'冰','Water':'水',
    'Earth':'大地','Light':'光','Celestial':'天界','Infernal':'炼狱',
    'Abyssal':'深渊','Void':'虚空','Chaos':'混沌','Arcane':'奥术',
    'Mystic':'神秘','Ethereal':'虚灵','Phantom':'幻影','Spectral':'幽灵',
    'Royal':'皇家','Imperial':'帝国','Dragon':'龙','Demon':'恶魔',
    'Angel':'天使','Phoenix':'凤凰','Fallen':'堕落','Twisted':'扭曲',
    'True':'真','Ultimate':'究极','Supreme':'至高','Grand':'宏伟',
    'Great':'大','Mighty':'强力','Eternal':'永恒','Immortal':'不朽',
    'Legendary':'传说','Mythic':'神话','Epic':'史诗',
    // Nouns
    'King':'王','Queen':'女王','Prince':'王子','Knight':'骑士','Warrior':'战士',
    'Mage':'法师','Wizard':'巫师','Witch':'女巫','Priest':'祭司',
    'Dragon':'龙','Serpent':'蛇','Wolf':'狼','Bear':'熊','Eagle':'鹰',
    'Raven':'乌鸦','Spider':'蜘蛛','Scorpion':'蝎子',
    'Tower':'塔','Castle':'城','Throne':'王座','Temple':'神殿','Altar':'祭坛',
    'Tomb':'墓','Ruins':'废墟','Abyss':'深渊','Heaven':'天堂','Hell':'地狱',
    'Forest':'森林','Mountain':'山','Ocean':'海','River':'河','Desert':'沙漠',
    'Sun':'太阳','Moon':'月','Star':'星','Sky':'天空','Night':'夜',
    'Death':'死亡','Life':'生命','Time':'时间','Fate':'命运','War':'战争',
    'Peace':'和平','Truth':'真理','Wisdom':'智慧','Power':'力量','Glory':'荣耀',
    'Wrath':'愤怒','Fury':'狂怒','Rage':'暴怒','Doom':'毁灭',
    // Prepositions
    'of':'之','the':'','from':'源自','and':'与',
  }
};

let exactNames = {};

export async function loadTranslationData() {
  try {
    const r = await fetch('data/item-names.json');
    if (r.ok) {
      exactNames = await r.json();
    }
  } catch(e) {}
}

export function translateItemName(name, locale) {
  if (locale === 'en') return name;

  // Check exact translation first
  if (exactNames[name]?.[locale]) return exactNames[name][locale];

  // Compositional translation
  const map = WORD_MAP[locale];
  if (!map) return name;

  // Try longest word matches first
  let result = name;
  const words = Object.keys(map).sort((a, b) => b.length - a.length);

  for (const word of words) {
    const regex = new RegExp('\\b' + word + '\\b', 'g');
    if (regex.test(result)) {
      result = result.replace(regex, map[word]);
    }
  }

  // Clean up: remove extra spaces, "의 의" patterns
  result = result.replace(/\s+/g, ' ').trim();
  result = result.replace(/의 의/g, '의');

  // If nothing changed, return original
  if (result === name) return name;

  return result;
}

// Build search index for a locale
export function buildLocalizedSearchIndex(itemIcons, locale) {
  if (locale === 'en') return itemIcons.map(icon => icon.name.toLowerCase());
  return itemIcons.map(icon => {
    const translated = translateItemName(icon.name, locale);
    // Include both original and translated for search
    return (icon.name + ' ' + translated).toLowerCase();
  });
}
