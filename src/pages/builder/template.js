import { t } from '../../i18n.js';

export function builderHTML() {
  return `
  <header>
    <div class="logo-area">
      <h1>TW<span>RPG</span> ${t('builder.title').replace('TWRPG ', '')}</h1>
      <p>${t('builder.subtitle')}</p>
    </div>
    <div class="header-actions">
      <button class="btn" onclick="openImport()">${t('builder.import')}</button>
      <button class="btn" onclick="exportData()">${t('builder.export')}</button>
      <span class="copy-btn-wrap">
        <button class="btn teal" onclick="copyToClipboard()">${t('builder.copyJson')}</button>
        <span class="copy-btn-tooltip">${t('builder.copyTooltip')}</span>
      </span>
    </div>
  </header>

  <div class="toolbar">
    <div class="custom-select-wrap" id="classPickerWrap">
      <div class="custom-select-trigger" id="classPickerTrigger" onclick="toggleClassDropdown()">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
          <circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>
        </svg>
        <span class="custom-select-label placeholder" id="classPickerLabel">${t('builder.selectClass')}</span>
        <svg class="custom-select-chevron" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
          <polyline points="6 9 12 15 18 9"/>
        </svg>
      </div>
      <div class="custom-select-dropdown" id="classPickerDropdown"></div>
    </div>
    <select id="classSelect" style="display:none"></select>
    <div class="custom-select-wrap" id="creatorPickerWrap" style="display:none; min-width:160px; max-width:220px;">
      <div class="custom-select-trigger" id="creatorPickerTrigger" onclick="toggleCreatorDropdown()">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
          <circle cx="12" cy="8" r="4"/><path d="M4 20c0-4 3.6-7 8-7s8 3 8 7"/>
        </svg>
        <span class="custom-select-label placeholder" id="creatorPickerLabel">${t('builder.chooseBuild')}</span>
        <svg class="custom-select-chevron" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
          <polyline points="6 9 12 15 18 9"/>
        </svg>
      </div>
      <div class="custom-select-dropdown" id="creatorPickerDropdown"></div>
    </div>
    <select id="creatorSelect" style="display:none" onchange="onCreatorChange()"></select>
    <button class="btn" id="resetTemplateBtn" onclick="resetToTemplate()" style="display:none">${t('builder.resetTemplate')}</button>
    <button class="btn danger-btn" id="clearAllBtn" onclick="clearAllRows()" style="display:none">${t('builder.clearAll')}</button>
  </div>

  <div class="table-wrap">
    <div class="table-scroll">
      <table id="grid">
        <thead>
          <tr>
            <th>
              <div id="heroColHeader">
                <div class="hero-col-icon-wrap" id="heroColIconWrap">
                  <span id="heroColIconPlaceholder">✦</span>
                  <img id="heroColIconImg" style="display:none" alt="">
                </div>
                <div>
                  <div id="heroColName">Heroes</div>
                  <div id="heroColSubtitle"></div>
                </div>
              </div>
            </th>
            <th><span class="th-icon">⚔️</span>${t('col.weapon')}</th>
            <th><span class="th-icon">⛑️</span>${t('col.helm')}</th>
            <th><span class="th-icon">🥋</span>${t('col.body')}</th>
            <th><span class="th-icon">🪽</span>${t('col.wings')}</th>
            <th><span class="th-icon">💍</span>${t('col.accessory')}</th>
          </tr>
        </thead>
        <tbody id="tbody"></tbody>
      </table>
      <div id="emptyState">
        <div class="es-icon">🗡️</div>
        <p>${t('builder.emptyState')}</p>
      </div>
    </div>
  </div>

  <div style="display:flex; justify-content:center; margin-top:14px;">
    <button class="btn primary" onclick="addRow()" style="padding: 10px 32px; font-size:13px;">${t('builder.addRow')}</button>
  </div>
`;
}
