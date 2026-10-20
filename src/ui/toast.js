let toastTimer;

// `action` ({ label, onClick }) adds a button, e.g. Undo; the toast then stays up longer.
export function showToast(msg, { action } = {}) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.toggle('has-action', !!action);
  if (action) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'toast-action';
    btn.textContent = action.label;
    btn.addEventListener('click', () => {
      clearTimeout(toastTimer);
      t.classList.remove('show');
      action.onClick();
    });
    t.append(btn);
  }
  t.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('show'), action ? 6000 : 3000);
}
