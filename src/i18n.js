const STRINGS = {
  en: {
    // Nav
    'nav.builder': 'Build Planner',
    'nav.items': 'Items',
    'nav.heroes': 'Heroes',
    'nav.bosses': 'Monsters',
    'nav.awakening': 'Awakening',
    'nav.builder.short': 'Builder',
    'nav.items.short': 'Items',
    'nav.heroes.short': 'Heroes',
    'nav.bosses.short': 'Boss',
    'nav.awakening.short': 'Awaken',

    // Builder
    'builder.title': 'Build Planner',
    'builder.subtitle': 'Loadout per Phase',
    'builder.import': 'Import',
    'builder.export': 'Export',
    'builder.copyJson': 'Copy JSON',
    'builder.copyTooltip': 'Submit to @Ruzai if you want your loadout uploaded.',
    'builder.selectClass': '— Select Hero Class —',
    'builder.chooseBuild': '— Choose build —',
    'builder.resetTemplate': '↺ Reset to template',
    'builder.clearAll': '🗑 Clear all rows',
    'builder.addRow': '+ Add Row',
    'builder.emptyState': 'No rows yet. Click <strong>+ Add Row</strong> below to get started.',

    // Picker
    'picker.title': 'Choose Icon',
    'picker.search': 'Search items...',
    'picker.allItems': 'All Items',
    'picker.searchPrompt': 'Search for an item by name',
    'picker.available': 'available',
    'picker.items': 'items',
    'picker.noMatch': 'No items match your search.',
    'picker.noData': 'No {slot} data yet',
    'picker.useSearch': 'Use search to find items by name',
    'picker.showing': 'Showing',
    'picker.from': 'from',

    // Columns
    'col.weapon': 'Weapon',
    'col.helm': 'Helm',
    'col.body': 'Body',
    'col.wings': 'Wings',
    'col.accessory': 'Accessory',

    // Stats
    'stat.STR': 'STR',
    'stat.AGI': 'AGI',
    'stat.INT': 'INT',

    // Pages
    'bosses.title': 'Monster Database',
    'bosses.subtitle': 'Stats, drops, and locations',
    'items.title': 'Item Database',
    'items.subtitle': 'Stats, effects, and recipes',
    'items.search': 'Search items...',

    // Common
    'common.back': '← Back',
    'common.madeBy': 'Made by Ruzai',
  },

  ko: {
    'nav.builder': '빌드 플래너',
    'nav.items': '아이템 도감',
    'nav.heroes': '영웅',
    'nav.bosses': '몬스터',
    'nav.awakening': '각성',
    'nav.builder.short': '빌더',
    'nav.heroes.short': '영웅',
    'nav.items.short': '아이템',
    'nav.bosses.short': '보스',
    'nav.awakening.short': '각성',

    'builder.title': 'TWRPG 빌드 플래너',
    'builder.subtitle': '페이즈별 장비',
    'builder.import': '가져오기',
    'builder.export': '내보내기',
    'builder.copyJson': 'JSON 복사',
    'builder.copyTooltip': '로드아웃을 업로드하려면 @Ruzai에게 제출하세요.',
    'builder.selectClass': '— 영웅 클래스 선택 —',
    'builder.chooseBuild': '— 빌드 선택 —',
    'builder.resetTemplate': '↺ 템플릿 초기화',
    'builder.clearAll': '🗑 모두 지우기',
    'builder.addRow': '+ 행 추가',
    'builder.emptyState': '아직 행이 없습니다. 아래의 <strong>+ 행 추가</strong>를 클릭하세요.',

    'picker.title': '아이콘 선택',
    'picker.search': '아이템 검색...',
    'picker.allItems': '전체 아이템',
    'picker.searchPrompt': '이름으로 아이템을 검색하세요',
    'picker.available': '사용 가능',
    'picker.items': '개 아이템',
    'picker.noMatch': '검색 결과가 없습니다.',
    'picker.noData': '{slot} 데이터 없음',
    'picker.useSearch': '검색으로 아이템을 찾으세요',
    'picker.showing': '표시 중',
    'picker.from': '출처',

    'col.weapon': '무기',
    'col.helm': '투구',
    'col.body': '갑옷',
    'col.wings': '날개',
    'col.accessory': '장신구',

    'stat.STR': '힘',
    'stat.AGI': '민첩',
    'stat.INT': '지능',

    'bosses.title': '몬스터 도감',
    'bosses.subtitle': '드롭, 정보 등',
    'items.title': '아이템 도감',
    'items.subtitle': '스탯, 레시피, 드롭 출처',
    'items.search': '아이템 검색...',

    'common.back': '← 뒤로',
    'common.madeBy': 'Made by Ruzai',
  },

  zh: {
    'nav.builder': '构建规划',
    'nav.items': '物品图鉴',
    'nav.heroes': '英雄',
    'nav.bosses': '怪物',
    'nav.awakening': '觉醒',
    'nav.builder.short': '搭配',
    'nav.heroes.short': '英雄',
    'nav.items.short': '物品',
    'nav.bosses.short': 'Boss',
    'nav.awakening.short': '觉醒',

    'builder.title': 'TWRPG 构建规划',
    'builder.subtitle': '每阶段装备',
    'builder.import': '导入',
    'builder.export': '导出',
    'builder.copyJson': '复制JSON',
    'builder.copyTooltip': '如需上传您的装备方案，请提交给 @Ruzai。',
    'builder.selectClass': '— 选择英雄职业 —',
    'builder.chooseBuild': '— 选择构建 —',
    'builder.resetTemplate': '↺ 重置模板',
    'builder.clearAll': '🗑 清空所有',
    'builder.addRow': '+ 添加行',
    'builder.emptyState': '暂无行。点击下方 <strong>+ 添加行</strong> 开始。',

    'picker.title': '选择图标',
    'picker.search': '搜索物品...',
    'picker.allItems': '全部物品',
    'picker.searchPrompt': '输入名称搜索物品',
    'picker.available': '可用',
    'picker.items': '个物品',
    'picker.noMatch': '没有匹配的物品。',
    'picker.noData': '暂无{slot}数据',
    'picker.useSearch': '使用搜索查找物品',
    'picker.showing': '显示',
    'picker.from': '来源',

    'col.weapon': '武器',
    'col.helm': '头盔',
    'col.body': '铠甲',
    'col.wings': '翅膀',
    'col.accessory': '饰品',

    'stat.STR': '力量',
    'stat.AGI': '敏捷',
    'stat.INT': '智力',

    'bosses.title': '怪物图鉴',
    'bosses.subtitle': '掉落、信息等',
    'items.title': '物品图鉴',
    'items.subtitle': '属性、配方、掉落来源',
    'items.search': '搜索物品...',

    'common.back': '← 返回',
    'common.madeBy': 'Made by Ruzai',
  }
};

const ROW_NAMES = {
  ko: {
    'Early': '초반', 'SD': 'SD', 'Tower': '탑', 'Aga': '아가',
    'Duke': '공작', 'Gaia': '가이아', 'AC': 'AC', 'Styrix': '스타릭스', 'Kam': '캄',
  },
  zh: {
    'Early': '前期', 'SD': 'SD', 'Tower': '塔', 'Aga': '阿加',
    'Duke': '公爵', 'Gaia': '盖亚', 'AC': 'AC', 'Styrix': '斯泰里克斯', 'Kam': '卡姆',
  }
};

const CLASS_NAMES = {
  ko: {
    'Berserker': '버서커', 'Blaster': '블래스터', 'Crusader': '크루세이더',
    'Dark Knight': '다크나이트', 'Fighter': '파이터', 'Knight': '나이트',
    'Lancer': '랜서', 'Lightseeker': '라이트시커', 'Merchant': '상인',
    'Paladin': '팔라딘', 'Sword Saint': '검성',
    'Assassin': '어쌔신', 'Bow Master': '보우마스터', 'Gunner': '거너',
    'Hermit': '은둔자', 'Martial Artist': '무도가', 'Phantom Blade': '팬텀블레이드',
    'Reaper': '리퍼', 'Shooter': '슈터', 'Sniper': '스나이퍼',
    'Sword Enchanter': '소드인챈터', 'Swordsman': '검사', 'Thunderer': '썬더러',
    'Trickster': '트릭스터',
    'Alchemist': '연금술사', 'Arcane Mage': '아케인메이지', 'Blood Weaver': '블러드위버',
    'Elementalist': '엘리멘탈리스트', 'Fire Mage': '화염술사', 'Lightning Mage': '번개술사',
    'Priest': '사제', 'Shrine Priestess': '무녀', 'Soul Weaver': '소울위버',
    'Warlock': '워록', 'Water Mage': '수마법사', 'Wind Mage': '풍마법사', 'Witch': '마녀',
  },
  zh: {
    'Berserker': '狂战士', 'Blaster': '爆破者', 'Crusader': '十字军',
    'Dark Knight': '暗黑骑士', 'Fighter': '格斗家', 'Knight': '骑士',
    'Lancer': '枪骑士', 'Lightseeker': '光明追寻者', 'Merchant': '商人',
    'Paladin': '圣骑士', 'Sword Saint': '剑圣',
    'Assassin': '刺客', 'Bow Master': '弓箭大师', 'Gunner': '枪手',
    'Hermit': '隐士', 'Martial Artist': '武术家', 'Phantom Blade': '幻影之刃',
    'Reaper': '死神', 'Shooter': '射手', 'Sniper': '狙击手',
    'Sword Enchanter': '剑魔', 'Swordsman': '剑士', 'Thunderer': '雷霆使者',
    'Trickster': '诡术师',
    'Alchemist': '炼金术士', 'Arcane Mage': '奥术法师', 'Blood Weaver': '血织者',
    'Elementalist': '元素使', 'Fire Mage': '火法师', 'Lightning Mage': '雷法师',
    'Priest': '牧师', 'Shrine Priestess': '巫女', 'Soul Weaver': '灵魂编织者',
    'Warlock': '术士', 'Water Mage': '水法师', 'Wind Mage': '风法师', 'Witch': '女巫',
  }
};

const STORAGE_KEY = 'twrpg_locale';
let currentLocale = localStorage.getItem(STORAGE_KEY) || 'en';

export function getLocale() {
  return currentLocale;
}

export function setLocale(locale) {
  if (!STRINGS[locale]) return;
  currentLocale = locale;
  localStorage.setItem(STORAGE_KEY, locale);
  document.documentElement.lang = locale;
  window.dispatchEvent(new CustomEvent('locale-change', { detail: { locale } }));
}

export function t(key, replacements) {
  let str = STRINGS[currentLocale]?.[key] || STRINGS.en[key] || key;
  if (replacements) {
    for (const [k, v] of Object.entries(replacements)) {
      str = str.replace(`{${k}}`, v);
    }
  }
  return str;
}

export function getItemName(item) {
  if (currentLocale === 'ko' && item.nameKo) return item.nameKo;
  if (currentLocale === 'zh' && item.nameZh) return item.nameZh;
  return item.name;
}

export function getClassName(name) {
  if (currentLocale === 'en') return name;
  return CLASS_NAMES[currentLocale]?.[name] || name;
}

export function getRowName(name) {
  if (currentLocale === 'en') return name;
  return ROW_NAMES[currentLocale]?.[name] || name;
}

let itemTranslations = { ko: {}, zh: {} };

export function loadItemTranslations(items) {
  itemTranslations = { ko: {}, zh: {} };
  items.forEach(item => {
    if (item.nameKo) itemTranslations.ko[item.name] = item.nameKo;
    if (item.nameZh) itemTranslations.zh[item.name] = item.nameZh;
  });
}

export function getIconName(name) {
  if (currentLocale === 'en') return name;
  return itemTranslations[currentLocale]?.[name] || name;
}

export function getAvailableLocales() {
  return [
    { code: 'en', label: 'English', flag: 'EN' },
    { code: 'ko', label: '한국어', flag: 'KR' },
    { code: 'zh', label: '中文', flag: 'CN' },
  ];
}
