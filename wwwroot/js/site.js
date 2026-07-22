// Global site JS: PDF export logic

document.addEventListener('DOMContentLoaded', function () {
	const pdfBtn = document.getElementById('pdfSaveBtn');
	if (pdfBtn) pdfBtn.addEventListener('click', handlePdfExport);
});

// --- Helper: Map chart card ID to checkbox ID ---
function getCheckboxIdForCard(cardId) {
	if (!cardId) return '';
	if (cardId === 'card_flow') return 'widget_fl';
	if (cardId.startsWith('card_')) return 'widget_' + cardId.replace('card_', '');
	return '';
}

// --- Helper: Collect visible cards based on checkbox state ---
function collectVisibleCards(sheet) {
	const allCards = Array.from(sheet.querySelectorAll('.chart-card'));
	const visibleCards = [];

	for (const card of allCards) {
		const checkboxId = getCheckboxIdForCard(card.id);
		if (checkboxId) {
			const checkbox = document.getElementById(checkboxId);
			if (checkbox && !checkbox.checked) continue;
		}
		const style = window.getComputedStyle(card);
		if (style.display === 'none') continue;
		visibleCards.push(card);
	}
	return visibleCards;
}

// --- Helper: Convert canvas to image element ---
function replaceCanvasWithImage(cardClone, originalCard) {
	const canvas = cardClone.querySelector('canvas.chart-canvas');
	if (!canvas) return;
	const originalCanvas = originalCard.querySelector('canvas.chart-canvas');
	let dataUrl = '';
	if (originalCanvas) {
		try { dataUrl = originalCanvas.toDataURL('image/png'); } catch (e) {}
	}
	const img = document.createElement('img');
	img.src = dataUrl;
	img.style.width = '100%';
	img.style.height = 'auto';
	img.style.maxHeight = 'none';
	img.style.objectFit = 'contain';
	canvas.parentNode.replaceChild(img, canvas);
}

// --- Helper: Style titles for print ---
function styleTitlesForPrint(cardClone) {
	const titles = cardClone.querySelectorAll('.editable-title, .chart-title, h5, h6, strong');
	titles.forEach(function(t) {
		t.style.color = '#000';
		t.style.visibility = 'visible';
		t.style.opacity = '1';
	});
}

// --- Helper: Style summary tables for print ---
function styleSummaryTables(cardClone) {
	const tables = cardClone.querySelectorAll('.summary-table, table');
	tables.forEach(function(t) {
		t.style.fontSize = '9px';
		t.style.marginTop = '4px';
		const ths = t.querySelectorAll('th');
		ths.forEach(function(th) { th.style.background = '#f0f0f0'; });
	});
}

// --- Helper: Clone a single card for PDF ---
function cloneCardForPdf(card) {
	const cardClone = card.cloneNode(true);
	cardClone.style.breakInside = 'avoid';
	cardClone.style.pageBreakInside = 'avoid';
	cardClone.style.background = 'white';
	cardClone.style.color = 'black';
	cardClone.style.border = '1px solid #ddd';
	cardClone.style.boxShadow = 'none';
	cardClone.style.padding = '6px';
	cardClone.style.display = 'block';
	cardClone.style.visibility = 'visible';
	cardClone.style.opacity = '1';

	replaceCanvasWithImage(cardClone, card);
	styleTitlesForPrint(cardClone);
	styleSummaryTables(cardClone);
	return cardClone;
}

// --- Helper: Build the print CSS string ---
function getPrintCss() {
	return '<style>' +
		'@page { size: A4 portrait; margin: 5mm; }' +
		'html, body { width: 210mm; min-height: 297mm; margin: 0; padding: 0; background: white; color: black; overflow: visible; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; color-adjust: exact !important; }' +
		'.paper-sheet { width: 210mm !important; min-height: 297mm !important; max-height: none !important; box-sizing: border-box; padding: 6mm !important; background: white !important; color: black !important; border: none !important; box-shadow: none !important; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }' +
		'.widget-grid { display: grid !important; gap: 6px !important; grid-template-columns: 1fr !important; grid-auto-flow: row !important; }' +
		'.widget-grid > .chart-card { display: block !important; width: 100% !important; visibility: visible !important; opacity: 1 !important; }' +
		'.chart-card { background: white !important; color: black !important; border: 1px solid #ddd !important; box-shadow: none !important; padding: 6px !important; page-break-inside: avoid; break-inside: avoid; }' +
		'.editable-title { color: #000 !important; font-size: 11px !important; font-weight: bold !important; display: block !important; visibility: visible !important; opacity: 1 !important; background: transparent !important; }' +
		'.summary-table { font-size: 9px !important; margin-top: 4px !important; }' +
		'.summary-table th { background: #f0f0f0 !important; }' +
		'.summary-table th, .summary-table td { color: black !important; border-color: #000 !important; padding: 2px 4px !important; background: white !important; }' +
		'.widget-header strong { color: black !important; font-size: 1rem !important; }' +
		'.chart-card img { width: 100% !important; height: auto !important; max-height: none !important; object-fit: contain !important; }' +
		'.custom-navbar, .control-panel, .custom-footer, .modal, .btn, button, input, select, label, .widget-selector { display: none !important; }' +
		'#reportHeader { background: #ffc107 !important; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; color-adjust: exact !important; color: #000 !important; display: block !important; padding: 4px 10px !important; border: 2px solid black !important; margin-bottom: 4px !important; font-size: 11px !important; }' +
		'#comparisonSection { display: block !important; margin-top: 6px !important; page-break-inside: avoid !important; }' +
		'#comparisonTable td, #comparisonTable th { color: #000 !important; border: 2px solid black !important; padding: 3px 6px !important; }' +
		'#comparisonTable th { background: #d4edda !important; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }' +
		'#comparisonTable td:nth-child(2), #comparisonTable td:nth-child(3), #comparisonTable td:nth-child(4), #comparisonTable th:nth-child(2), #comparisonTable th:nth-child(3), #comparisonTable th:nth-child(4) { background: #e8f5e9 !important; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }' +
		'#comparisonTable td:nth-child(5), #comparisonTable td:nth-child(6), #comparisonTable th:nth-child(5), #comparisonTable th:nth-child(6) { background: #fff3e0 !important; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }' +
	'</style>';
}

// --- Helper: Build the HTML head for print window ---
function buildPrintHead() {
	const origin = window.location.origin;
	const cssFiles = [
		origin + '/lib/bootstrap/dist/css/bootstrap.min.css',
		origin + '/css/site.css',
		origin + '/css/charts.css'
	];
	const linkTags = cssFiles.map(function(href) {
		return '<link rel="stylesheet" href="' + href + '">';
	}).join('');
	return '<meta charset="utf-8"><title>Export PDF</title>' + linkTags + getPrintCss();
}

// --- Main PDF export handler ---
async function handlePdfExport() {
	const sheet = document.querySelector('.paper-sheet');
	if (!sheet) return;

	// Create clone container
	const clone = document.createElement('div');
	clone.className = 'paper-sheet';
	clone.style.width = '210mm';
	clone.style.minHeight = '297mm';
	clone.style.maxHeight = 'none';
	clone.style.boxSizing = 'border-box';
	clone.style.padding = '6mm';
	clone.style.background = 'white';
	clone.style.color = 'black';
	clone.style.border = 'none';
	clone.style.boxShadow = 'none';

	// Clone report header
	const reportHeader = document.getElementById('reportHeader');
	if (reportHeader) {
		const headerClone = reportHeader.cloneNode(true);
		headerClone.style.display = 'block';
		headerClone.style.visibility = 'visible';
		headerClone.style.opacity = '1';
		headerClone.style.background = '#ffc107';
		headerClone.style.color = '#000';
		clone.appendChild(headerClone);
	}

	// Collect and clone visible cards
	const visibleCards = collectVisibleCards(sheet);
	if (visibleCards.length === 0) {
		alert('Dışa aktarılacak grafik yok. Lütfen en az bir widget seçin.');
		return;
	}

	const grid = document.createElement('div');
	grid.className = 'widget-grid';
	grid.style.display = 'grid';
	grid.style.gap = '6px';
	grid.style.gridTemplateColumns = '1fr';
	grid.style.gridAutoFlow = 'row';

	visibleCards.forEach(function(card) {
		grid.appendChild(cloneCardForPdf(card));
	});
	clone.appendChild(grid);

	// Clone comparison section
	const comparisonSection = document.getElementById('comparisonSection');
	if (comparisonSection && comparisonSection.style.display !== 'none') {
		const compClone = comparisonSection.cloneNode(true);
		compClone.style.display = 'block';
		compClone.style.visibility = 'visible';
		compClone.style.opacity = '1';
		const compTds = compClone.querySelectorAll('td, th');
		compTds.forEach(function(td) { td.style.color = '#000'; });
		clone.appendChild(compClone);
	}

	// Build and open print window using DOM manipulation instead of document.write
	const w = window.open('', '_blank');
	if (!w) {
		alert('Popup engelendi. Lütfen tarayıcınızda popup\'lara izin verin.');
		return;
	}

	const doc = w.document;
	doc.head.innerHTML = buildPrintHead();
	doc.body.innerHTML = clone.outerHTML;
	w.focus();
	setTimeout(function() { try { w.print(); } catch (e) {} }, 800);
}
