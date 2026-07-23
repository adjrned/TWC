const TRACKER_KEY = 'twrpg_tracker';
const PROFILES_KEY = 'twrpg_profiles';
const LOADCODE_KEY = 'twrpg_loadcodes';
const MAX_HISTORY = 10;

export function loadProfiles() {
  try {
    const raw = localStorage.getItem(PROFILES_KEY);
    if (raw) {
      const data = JSON.parse(raw);
      if (data && data.version === 1) return data;
    }
  } catch (e) {}
  return { version: 1, activeProfileId: null, profiles: [] };
}

export function saveProfiles(data) {
  try {
    localStorage.setItem(PROFILES_KEY, JSON.stringify(data));
  } catch (e) {}
}

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

export function getProfileStorageKey(profileId) {
  return `twrpg_profile_${profileId}`;
}

export function loadProfileState(profileId) {
  try {
    const raw = localStorage.getItem(getProfileStorageKey(profileId));
    if (raw) {
      const s = JSON.parse(raw);
      if (s && s.version === 1) return s;
    }
  } catch (e) {}
  return { version: 1, trackedItems: [], lastSave: null };
}

export function saveProfileState(profileId, state) {
  try {
    localStorage.setItem(getProfileStorageKey(profileId), JSON.stringify(state));
  } catch (e) {}
}

export function deleteProfileState(profileId) {
  try {
    localStorage.removeItem(getProfileStorageKey(profileId));
  } catch (e) {}
}

export function migrateToProfiles() {
  const profilesData = loadProfiles();
  if (profilesData.profiles.length > 0) return profilesData;

  const legacy = loadTrackerState();
  if (!legacy.lastSave && !legacy.trackedItems.length) return profilesData;

  const id = Date.now().toString(36);
  const name = legacy.lastSave
    ? `${legacy.lastSave.username} (${legacy.lastSave.class})`
    : 'Default';

  profilesData.profiles.push({ id, name, createdAt: Date.now() });
  profilesData.activeProfileId = id;
  saveProfileState(id, legacy);
  saveProfiles(profilesData);
  return profilesData;
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
