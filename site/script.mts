// The page's enhancements, bundled with the demos by demos/main.tsx: the menu
// button on narrow screens and a copy button on every command. Without
// JavaScript the menu is a plain list of links and the commands can be selected.

const toggle = document.querySelector<HTMLButtonElement>(".nav-toggle");
const nav = document.getElementById("site-nav");

if (toggle && nav) {
  toggle.hidden = false;
  const close = () => {
    toggle.setAttribute("aria-expanded", "false");
    nav.dataset["open"] = "false";
  };
  close();
  toggle.addEventListener("click", () => {
    const open = toggle.getAttribute("aria-expanded") !== "true";
    toggle.setAttribute("aria-expanded", String(open));
    nav.dataset["open"] = String(open);
  });
  nav.addEventListener("click", (event) => {
    if ((event.target as HTMLElement).closest("a")) close();
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && toggle.getAttribute("aria-expanded") === "true") {
      close();
      toggle.focus();
    }
  });
}

const status = document.createElement("p");
status.className = "visually-hidden";
status.setAttribute("role", "status");
document.body.append(status);

const icon = (name: string) => `<svg aria-hidden="true"><use href="#i-${name}" /></svg>`;

for (const block of document.querySelectorAll<HTMLElement>(".code-block")) {
  const pre = block.querySelector("pre");
  if (!pre) continue;
  const button = document.createElement("button");
  button.type = "button";
  button.className = "copy-button";
  button.innerHTML = `${icon("copy")}<span class="visually-hidden">Copy the commands</span>`;
  button.addEventListener("click", () => {
    const copy = pre.cloneNode(true) as HTMLElement;
    copy.querySelectorAll(".prompt, .comment").forEach((part) => part.remove());
    const text = copy.textContent.split("\n").map((line) => line.trim()).filter(Boolean).join("\n");
    navigator.clipboard.writeText(text).then(
      () => {
        button.innerHTML = `${icon("check")}<span class="visually-hidden">Copied</span>`;
        status.textContent = "Copied the commands.";
        setTimeout(() => {
          button.innerHTML = `${icon("copy")}<span class="visually-hidden">Copy the commands</span>`;
        }, 2000);
      },
      () => {
        status.textContent = "Couldn't copy: select the commands and copy them instead.";
      },
    );
  });
  block.querySelector(".code-block__bar")?.append(button);
}
