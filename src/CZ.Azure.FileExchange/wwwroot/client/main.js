export function copyText(text) {
  navigator.clipboard.writeText(text).then(() => {
  }).catch((error) => {
    alert(error);
  });
}
