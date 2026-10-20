import { t } from '../../i18n.js';
import { COLS } from '../../constants.js';
import { slotIcon } from '../../ui/slotIcons.js';

const CHEVRON = '<svg class="custom-select-chevron" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="6 9 12 15 18 9"/></svg>';

export function builderHTML() {
  return `
  <div class="page-header">
    <h1>${t('builder.title')}</h1>
    <p class="page-subtitle">${t('builder.subtitle')}</p>
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
    <span class="bp-build-date" id="bpBuildDate"></span>
    <span class="bp-toolbar-spacer"></span>
    <button type="button" class="btn bp-share-btn" id="bpShareBtn" title="${t('builder.shareHint')}" hidden>
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M10 14a4.5 4.5 0 0 0 6.4 0l3.2-3.2a4.5 4.5 0 0 0-6.4-6.4L12 5.6"/><path d="M14 10a4.5 4.5 0 0 0-6.4 0l-3.2 3.2a4.5 4.5 0 0 0 6.4 6.4l1.2-1.2"/></svg>
      <span>${t('builder.share')}</span>
    </button>
    <div class="bp-more" id="bpMore">
      <button type="button" class="btn bp-more-btn" id="bpMoreBtn" aria-haspopup="menu" aria-expanded="false" title="${t('builder.more')}">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>
        <span>${t('builder.more')}</span>
      </button>
      <div class="bp-more-menu" id="bpMoreMenu" role="menu" hidden>
        <button type="button" role="menuitem" data-act="import">${t('builder.import')}</button>
        <button type="button" role="menuitem" data-act="export">${t('builder.export')}</button>
        <button type="button" role="menuitem" data-act="copy">${t('builder.copyJson')}<small>${t('builder.copyTooltip')}</small></button>
        <hr>
        <button type="button" role="menuitem" data-act="reset" id="resetTemplateBtn" hidden>${t('builder.resetTemplate')}</button>
        <button type="button" role="menuitem" data-act="clear" id="clearAllBtn" class="danger" hidden>${t('builder.clearAll')}</button>
      </div>
    </div>
  </div>

  <div id="buildBrowser" hidden></div>

  <section class="bp-hero" id="bpHero" hidden>
    <a class="bp-hero-portrait" id="bpHeroPortrait"><img id="bpHeroImg" alt=""></a>
    <div class="bp-hero-main">
      <p class="bp-hero-sub" id="bpHeroSub"></p>
      <p class="bp-hero-overview" id="bpHeroOverview"></p>
      <div class="bp-hero-skills" id="bpHeroSkills"></div>
    </div>
  </section>

  <div id="bpEmpty" class="bp-empty">
    <div class="bp-empty-icons">${COLS.map(c => slotIcon(c, 22)).join('')}</div>
    <p>${t('builder.pickClassPrompt')}</p>
  </div>

  <div class="table-wrap" id="bpGrid" hidden>
    <div class="table-scroll">
      <table id="grid" class="bp-table">
        <thead>
          <tr>
            <th class="bp-hero-th">${t('builder.phase')}</th>
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
