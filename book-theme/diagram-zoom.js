// Show a rendered Mermaid diagram at its natural size in a dialog.
// Large architecture diagrams shrink to the column width; this makes them legible.
(() => {
    const dialog = document.createElement('dialog');
    dialog.className = 'diagram-dialog';
    const bar = document.createElement('div');
    bar.className = 'diagram-bar';
    const close = document.createElement('button');
    close.type = 'button';
    close.textContent = 'Close';
    close.setAttribute('aria-label', 'Close diagram');
    close.addEventListener('click', () => dialog.close());
    bar.append(close);
    const canvas = document.createElement('div');
    canvas.className = 'diagram-canvas';
    dialog.append(bar, canvas);

    // Mermaid scopes its styles by the SVG's id, so the dialog borrows the
    // rendered node and hands it back on close instead of cloning it.
    let restore = null;
    const open = (diagram) => {
        const svg = diagram.querySelector('svg');
        if (!svg || restore) {
            return;
        }
        const saved = ['width', 'height', 'style'].map((name) => [name, svg.getAttribute(name)]);
        const box = svg.viewBox.baseVal;
        svg.removeAttribute('style');
        svg.setAttribute('width', Math.ceil(box.width));
        svg.setAttribute('height', Math.ceil(box.height));
        diagram.style.minHeight = `${diagram.offsetHeight}px`;
        canvas.replaceChildren(svg);
        restore = () => {
            for (const [name, value] of saved) {
                if (value === null) {
                    svg.removeAttribute(name);
                } else {
                    svg.setAttribute(name, value);
                }
            }
            diagram.replaceChildren(svg);
            diagram.style.minHeight = '';
            diagram.focus({ preventScroll: true });
        };
        if (!dialog.isConnected) {
            document.body.append(dialog);
        }
        dialog.showModal();
    };
    dialog.addEventListener('close', () => {
        if (restore) {
            restore();
            restore = null;
        }
    });

    for (const diagram of document.querySelectorAll('pre.mermaid')) {
        diagram.tabIndex = 0;
        diagram.setAttribute('role', 'button');
        diagram.setAttribute('aria-label', 'Enlarge diagram');
    }
    document.addEventListener('click', (event) => {
        if (event.target === dialog) {
            dialog.close();
            return;
        }
        const diagram = event.target.closest('pre.mermaid');
        if (diagram && !dialog.contains(diagram)) {
            open(diagram);
        }
    });
    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && dialog.open) {
            dialog.close();
            return;
        }
        if ((event.key === 'Enter' || event.key === ' ') && event.target.matches('pre.mermaid')) {
            event.preventDefault();
            open(event.target);
        }
    });
})();
