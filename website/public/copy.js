// "Kopyala" buttons next to install commands
for (const btn of document.querySelectorAll('[data-copy]')) {
  btn.addEventListener('click', async () => {
    await navigator.clipboard.writeText(document.getElementById(btn.dataset.copy).textContent.trim());
    btn.textContent = 'Kopyalandı ✓';
    setTimeout(() => (btn.textContent = 'Kopyala'), 2000);
  });
}
