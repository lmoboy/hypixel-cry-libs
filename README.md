
# 🛠 Contributing to the Library Registry

Thank you for your interest in contributing! To keep the registry organized and automated, please follow these steps.

---

## 🚀 Quick Start Guide

### 1. Setup
Clone the repository to your local machine:
```bash
git clone [https://github.com/YourUsername/YourRepository.git](https://github.com/YourUsername/YourRepository.git)

```

### 2. Add Your Script

Place your `.lua` library or script into the `/src` directory.

### 3. Add Metadata (Required)

To ensure the registry updates correctly, add these two lines to the **very top** of your Lua file:

```lua
-- @version 1.0.0
-- @location /libs/

```

> [!NOTE]
> If these comments are missing, the system will default to:
> * **Version:** `alpha-0.1`
> * **Location:** `/libs/`
> 
> 

---

## ⚠️ Strict Submission Rules

Our automated system manages all Pull Requests. Please be aware of the following:

* **Lua Only:** This repository **only** accepts `.lua` files.
* **No Extra Files:** If your Pull Request contains any non-Lua files (e.g., `.txt`, `.md`, `.zip`), the PR will be **automatically closed** by the system.
* **One Step Merge:** Once you open a PR with valid Lua files, our GitHub Action will:
1. Validate the file types.
2. Extract your metadata.
3. Update `registry.json`.
4. Auto-approve and merge your contribution.



---

## 📬 How to Submit

1. **Branch:** Create a new branch for your feature (`git checkout -b feature/my-library`).
2. **Commit:** Commit your changes (`git commit -m "Add my-library.lua"`).
3. **Push:** Push to your fork or branch.
4. **Pull Request:** Open a PR against the `main` branch.

**Happy Coding!** 💻
