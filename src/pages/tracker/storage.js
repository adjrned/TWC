const TRACKER_KEY = 'twrpg_tracker';
const LOADCODE_KEY = 'twrpg_loadcodes';
const MAX_HISTORY = 10;

export function loadTrackerState() {
  try {
    const raw = localStorage.getItem(TRACKER_KEY);
    if (raw) {
      const s = JSON.parse(raw);
      if (s && s.version === 1) return s;
    }
  } catch (e) {}
  return { version: 1, trackedItems: [], lastSave: null };
}

export function saveTrackerState(state) {
  try {
    localStorage.setItem(TRACKER_KEY, JSON.stringify(state));
  } catch (e) {}
}

export function loadCodeHistory() {
  try {
    const raw = localStorage.getItem(LOADCODE_KEY);
    if (raw) return JSON.parse(raw) || [];
  } catch (e) {}
  return [];
}

export function addCodeHistoryEntry(entry) {
  const history = loadCodeHistory();
  history.unshift(entry);
  if (history.length > MAX_HISTORY) history.length = MAX_HISTORY;
  try {
    localStorage.setItem(LOADCODE_KEY, JSON.stringify(history));
  } catch (e) {}
}
