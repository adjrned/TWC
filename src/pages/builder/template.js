import { t } from '../../i18n.js';
import { COLS } from '../../constants.js';
import { slotIcon } from '../../ui/slotIcons.js';

const CHEVRON = '<svg class="custom-select-chevron" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="6 9 12 15 18 9"/></svg>';

export function builderHTML() {
  return `
  <div class="page-header page-header-actions">
    <div class="page-header-titles">
      <h1>${t('builder.title')}</h1>
      <p class="page-subtitle">${t('builder.subtitle')}</p>
    </div>
    <div class="header-actions">
      <button class="btn" onclick="openImport()">${t('builder.import')}</button>
      <button class="btn" onclick="exportData()">${t('builder.export')}</button>
      <span class="copy-btn-wrap">
        <button class="btn" onclick="copyToClipboard()">${t('builder.copyJson')}</button>
        <span class="copy-btn-tooltip">${t('builder.copyTooltip')}</span>
      </span>
    </div>
  </div>

  <div class="bp-toolbar">
    <div class="custom-select-wrap" id="classPickerWrap">
      <div class="custom-select-trigger" id="classPickerTrigger" onclick="toggleClassDropdown()">
        <img id="classPickerIcon" class="bp-class-icon" alt="" hidden>
        <span class="custom-select-label placeholder" id="classPickerLabel">${t('builder.selectClass')}</span>
        ${CHEVRON}
      </div>
      <div class="custom-select-dropdown" id="classPickerDropdown"></div>
    </div>
    <button type="button" class="bp-buildbtn" id="buildBrowserBtn" onclick="toggleBuildBrowser()" hidden>
      <span class="bp-buildbtn-label">${t('builder.build')}</span>
      <span class="bp-buildbtn-value" id="buildBrowserValue"></span>
      ${CHEVRON}
    </button>
    <span class="bp-toolbar-spacer"></span>
    <button class="btn" id="resetTemplateBtn" onclick="resetToTemplate()" hidden>${t('builder.resetTemplate')}</button>
    <button class="btn danger-btn" id="clearAllBtn" onclick="clearAllRows()" hidden>${t('builder.clearAll')}</button>
  </div>

  <div id="buildBrowser" hidden></div>

  <div id="bpEmpty" class="bp-empty">
    <div class="bp-empty-icons">${COLS.map(c => slotIcon(c, 22)).join('')}</div>
    <p>${t('builder.pickClassPrompt')}</p>
  </div>

  <div class="table-wrap" id="bpGrid" hidden>
    <div class="table-scroll">
      <table id="grid" class="bp-table">
        <thead>
          <tr>
            <th class="bp-hero-th">
              <div id="heroColHeader">
                <div class="hero-col-icon-wrap" id="heroColIconWrap">
                  <span id="heroColIconPlaceholder"></span>
                  <img id="heroColIconImg" style="display:none" alt="">
                </div>
                <div class="hero-col-text">
                  <div id="heroColName"></div>
                  <div id="heroColSubtitle"></div>
                </div>
              </div>
            </th>
            ${COLS.map(c => `<th class="bp-col-th"><span class="th-icon">${slotIcon(c, 20)}</span><span class="th-label">${t('col.' + c)}</span></th>`).join('')}
          </tr>
        </thead>
        <tbody id="tbody"></tbody>
      </table>
      <div id="emptyState">
        <p>${t('builder.emptyState')}</p>
      </div>
    </div>
    <div class="bp-foot">
      <button class="btn" onclick="addRow()">${t('builder.addRow')}</button>
      <span class="bp-hint">${t('builder.hint')}</span>
    </div>
  </div>
`;
}
