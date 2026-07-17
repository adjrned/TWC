export const builderHTML = `
  <header>
    <div class="logo-area">
      <h1>TW<span>RPG</span> Loadout Builder</h1>
      <p>Build Planner</p>
    </div>
    <div class="header-actions">
      <button class="btn" onclick="openImport()">Import</button>
      <button class="btn" onclick="exportData()">Export</button>
      <span class="copy-btn-wrap">
        <button class="btn teal" onclick="copyToClipboard()">Copy JSON</button>
        <span class="copy-btn-tooltip">Submit to @Ruzai if you want your loadout uploaded.</span>
      </span>
    </div>
  </header>

  <div class="toolbar">
    <div class="custom-select-wrap" id="classPickerWrap">
      <div class="custom-select-trigger" id="classPickerTrigger" onclick="toggleClassDropdown()">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
          <circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>
        </svg>
        <span class="custom-select-label placeholder" id="classPickerLabel">— Select Hero Class —</span>
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
        <span class="custom-select-label placeholder" id="creatorPickerLabel">— Choose build —</span>
        <svg class="custom-select-chevron" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
          <polyline points="6 9 12 15 18 9"/>
        </svg>
      </div>
      <div class="custom-select-dropdown" id="creatorPickerDropdown"></div>
    </div>
    <select id="creatorSelect" style="display:none" onchange="onCreatorChange()"></select>
    <button class="btn" id="resetTemplateBtn" onclick="resetToTemplate()" style="display:none" title="Discard local edits and reload the published build">↺ Reset to template</button>
    <button class="btn danger-btn" id="clearAllBtn" onclick="clearAllRows()" style="display:none" title="Clear all items from every row">🗑 Clear all rows</button>
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
            <th><span class="th-icon">⚔️</span>Weapon</th>
            <th><span class="th-icon">⛑️</span>Helm</th>
            <th><span class="th-icon">🥋</span>Body</th>
            <th><span class="th-icon">🪽</span>Wings</th>
            <th><span class="th-icon">💍</span>Accessory</th>
          </tr>
        </thead>
        <tbody id="tbody"></tbody>
      </table>
      <div id="emptyState">
        <div class="es-icon">🗡️</div>
        <p>No rows yet. Click <strong>+ Add Row</strong> below to get started.</p>
      </div>
    </div>
  </div>

  <div style="display:flex; justify-content:center; margin-top:14px;">
    <button class="btn primary" onclick="addRow()" style="padding: 10px 32px; font-size:13px;">+ Add Row</button>
  </div>
`;
