// Global site JS: PDF export logic
document.addEventListener('DOMContentLoaded', function () {

	const pdfBtn = document.getElementById('pdfSaveBtn');
	if (pdfBtn) pdfBtn.addEventListener('click', async function () {
		const sheet = document.querySelector('.paper-sheet');
		if (!sheet) return;

		// --- Klon oluştur ---
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

		// --- Report Header (Üst Bilgi Şeridi) ---
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

		// --- Grid (Sadece checkbox'ı işaretli widget'ları dahil et) ---
		const allCards = Array.from(sheet.querySelectorAll('.chart-card'));
		const visibleCards = [];

		for (const card of allCards) {
			const cardId = card.id;
			let checkboxId = '';
			if (cardId === 'card_flow') checkboxId = 'widget_fl';
			else if (cardId.startsWith('card_')) {
				const suffix = cardId.replace('card_', '');
				checkboxId = `widget_${suffix}`;
			}

			if (checkboxId) {
				const checkbox = document.getElementById(checkboxId);
				if (checkbox && !checkbox.checked) continue;
			}

			const style = window.getComputedStyle(card);
			if (style.display === 'none') continue;

			visibleCards.push(card);
		}

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

		// Görünür kartları klonla
		visibleCards.forEach(card => {
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

			// Canvas'ı image'a dönüştür
			const canvas = cardClone.querySelector('canvas.chart-canvas');
			if (canvas) {
				const originalCanvas = card.querySelector('canvas.chart-canvas');
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

			// Başlıkları siyah yap
			const titles = cardClone.querySelectorAll('.editable-title, .chart-title, h5, h6, strong');
			titles.forEach(t => {
				t.style.color = '#000';
				t.style.visibility = 'visible';
				t.style.opacity = '1';
			});

			// Özet tablo stilleri
			const tables = cardClone.querySelectorAll('.summary-table, table');
			tables.forEach(t => {
				t.style.fontSize = '9px';
				t.style.marginTop = '4px';
				const ths = t.querySelectorAll('th');
				ths.forEach(th => th.style.background = '#f0f0f0');
			});

			grid.appendChild(cardClone);
		});

		clone.appendChild(grid);

		// --- Comparison Section (GSV/Mass Tablosu) ---
		const comparisonSection = document.getElementById('comparisonSection');
		if (comparisonSection && comparisonSection.style.display !== 'none') {
			const compClone = comparisonSection.cloneNode(true);
			compClone.style.display = 'block';
			compClone.style.visibility = 'visible';
			compClone.style.opacity = '1';

			// Tablo hücrelerine siyah renk ekle
			const compTds = compClone.querySelectorAll('td, th');
			compTds.forEach(td => {
				td.style.color = '#000';
			});

			clone.appendChild(compClone);
		}

		// Print window CSS
		const origin = window.location.origin;
		const cssLinks = [
			`${origin}/lib/bootstrap/dist/css/bootstrap.min.css`,
			`${origin}/css/site.css`,
			`${origin}/css/charts.css`
		];
		const head = `<meta charset="utf-8"><title>Export PDF</title>`
			+ cssLinks.map(h => `<link rel="stylesheet" href="${h}">`).join('')
			+ `<style>
				@page { size: A4 portrait; margin: 5mm; }
				html, body { width: 210mm; min-height: 297mm; margin: 0; padding: 0; background: white; color: black; overflow: visible; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; color-adjust: exact !important; }
				.paper-sheet { width: 210mm !important; min-height: 297mm !important; max-height: none !important; box-sizing: border-box; padding: 6mm !important; background: white !important; color: black !important; border: none !important; box-shadow: none !important; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
				.widget-grid { display: grid !important; gap: 6px !important; grid-template-columns: 1fr !important; grid-auto-flow: row !important; }
				.widget-grid > .chart-card { display: block !important; width: 100% !important; visibility: visible !important; opacity: 1 !important; }
				.chart-card { background: white !important; color: black !important; border: 1px solid #ddd !important; box-shadow: none !important; padding: 6px !important; page-break-inside: avoid; break-inside: avoid; }
				.editable-title { color: #000 !important; font-size: 11px !important; font-weight: bold !important; display: block !important; visibility: visible !important; opacity: 1 !important; background: transparent !important; }
				.summary-table { font-size: 9px !important; margin-top: 4px !important; }
				.summary-table th { background: #f0f0f0 !important; }
				.summary-table th, .summary-table td { color: black !important; border-color: #000 !important; padding: 2px 4px !important; background: white !important; }
				.widget-header strong { color: black !important; font-size: 1rem !important; }
				.chart-card img { width: 100% !important; height: auto !important; max-height: none !important; object-fit: contain !important; }
				.custom-navbar, .control-panel, .custom-footer, .modal, .btn, button, input, select, label, .widget-selector { display: none !important; }
				#reportHeader { background: #ffc107 !important; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; color-adjust: exact !important; color: #000 !important; display: block !important; padding: 4px 10px !important; border: 2px solid black !important; margin-bottom: 4px !important; font-size: 11px !important; }
				#comparisonSection { display: block !important; margin-top: 6px !important; page-break-inside: avoid !important; }
				#comparisonTable td, #comparisonTable th { color: #000 !important; border: 2px solid black !important; padding: 3px 6px !important; }
				#comparisonTable th { background: #d4edda !important; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
				#comparisonTable td:nth-child(2), #comparisonTable td:nth-child(3), #comparisonTable td:nth-child(4), #comparisonTable th:nth-child(2), #comparisonTable th:nth-child(3), #comparisonTable th:nth-child(4) { background: #e8f5e9 !important; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
				#comparisonTable td:nth-child(5), #comparisonTable td:nth-child(6), #comparisonTable th:nth-child(5), #comparisonTable th:nth-child(6) { background: #fff3e0 !important; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
			</style>`;

		const w = window.open('', '_blank');
		w.document.open();
		w.document.write(`<!doctype html><html><head>${head}</head><body>${clone.outerHTML}</body></html>`);
		w.document.close();
		w.focus();
		setTimeout(() => { try { w.print(); } catch (e) {} }, 800);
	});
});
