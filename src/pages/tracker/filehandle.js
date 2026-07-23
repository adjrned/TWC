const DB_NAME = 'twrpg_filehandles';
const STORE_NAME = 'handles';
const DB_VERSION = 1;

function openDB() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      req.result.createObjectStore(STORE_NAME);
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

export async function storeFileHandle(profileId, handle) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readwrite');
    tx.objectStore(STORE_NAME).put(handle, profileId);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

export async function getFileHandle(profileId) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readonly');
    const req = tx.objectStore(STORE_NAME).get(profileId);
    req.onsuccess = () => resolve(req.result || null);
    req.onerror = () => reject(req.error);
  });
}

export async function removeFileHandle(profileId) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readwrite');
    tx.objectStore(STORE_NAME).delete(profileId);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

export async function readFileFromHandle(handle) {
  const permission = await handle.queryPermission({ mode: 'read' });
  if (permission === 'granted') {
    const file = await handle.getFile();
    return file.text();
  }
  const requested = await handle.requestPermission({ mode: 'read' });
  if (requested === 'granted') {
    const file = await handle.getFile();
    return file.text();
  }
  return null;
}

export function supportsFileHandles() {
  return 'showOpenFilePicker' in window;
}

export async function pickFile() {
  const [handle] = await window.showOpenFilePicker({
    types: [{ description: 'WC3 Save File', accept: { 'text/plain': ['.txt'] } }],
  });
  const file = await handle.getFile();
  const text = await file.text();
  return { handle, text, fileName: file.name };
}
