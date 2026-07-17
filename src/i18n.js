const STRINGS = {
  en: {
    // Nav
    'nav.builder': 'Loadout Builder',
    'nav.items': 'Item Repository',
    'nav.bosses': 'Boss Guides',
    'nav.builder.short': 'Builder',
    'nav.items.short': 'Items',
    'nav.bosses.short': 'Bosses',

    // Builder
    'builder.title': 'TWRPG Loadout Builder',
    'builder.subtitle': 'Build Planner',
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
    'bosses.title': 'Boss Guides',
    'bosses.subtitle': 'Strategies, phases, and drop tables for every boss',
    'items.title': 'Item Repository',
    'items.subtitle': 'Full item database — stats, recipes, and drop sources',
    'items.search': 'Search items...',

    // Common
    'common.back': '← Back',
    'common.madeBy': 'Made by Ruzai',
  },

  ko: {
    'nav.builder': '장비 빌더',
    'nav.items': '아이템 도감',
    'nav.bosses': '보스 공략',
    'nav.builder.short': '빌더',
    'nav.items.short': '아이템',
    'nav.bosses.short': '보스',

    'builder.title': 'TWRPG 장비 빌더',
    'builder.subtitle': '빌드 플래너',
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

    'bosses.title': '보스 공략',
    'bosses.subtitle': '모든 보스의 전략, 페이즈, 드롭 테이블',
    'items.title': '아이템 도감',
    'items.subtitle': '전체 아이템 데이터베이스 — 스탯, 레시피, 드롭 출처',
    'items.search': '아이템 검색...',

    'common.back': '← 뒤로',
    'common.madeBy': 'Made by Ruzai',
  },

  zh: {
    'nav.builder': '装备搭配',
    'nav.items': '物品图鉴',
    'nav.bosses': 'Boss攻略',
    'nav.builder.short': '搭配',
    'nav.items.short': '物品',
    'nav.bosses.short': 'Boss',

    'builder.title': 'TWRPG 装备搭配',
    'builder.subtitle': '构建规划器',
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

    'bosses.title': 'Boss攻略',
    'bosses.subtitle': '所有Boss的策略、阶段和掉落表',
    'items.title': '物品图鉴',
    'items.subtitle': '完整物品数据库 — 属性、配方、掉落来源',
    'items.search': '搜索物品...',

    'common.back': '← 返回',
    'common.madeBy': 'Made by Ruzai',
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

export function getAvailableLocales() {
  return [
    { code: 'en', label: 'English', flag: 'EN' },
    { code: 'ko', label: '한국어', flag: 'KR' },
    { code: 'zh', label: '中文', flag: 'CN' },
  ];
}
