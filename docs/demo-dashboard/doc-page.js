const imageDialog = document.querySelector("#imageDialog");
const imageDialogTitle = document.querySelector("#imageDialogTitle");
const imageDialogPreview = document.querySelector("#imageDialogPreview");
const closeImageDialog = document.querySelector("#closeImageDialog");

document.querySelectorAll(".image-preview").forEach((button) => {
  button.addEventListener("click", () => {
    imageDialogTitle.textContent = button.dataset.title || "Evidence screenshot";
    imageDialogPreview.src = button.dataset.full;
    imageDialogPreview.alt = button.dataset.title || "Evidence screenshot";
    imageDialog.showModal();
  });
});

closeImageDialog?.addEventListener("click", () => {
  imageDialog.close();
});

imageDialog?.addEventListener("click", (event) => {
  if (event.target === imageDialog) {
    imageDialog.close();
  }
});
