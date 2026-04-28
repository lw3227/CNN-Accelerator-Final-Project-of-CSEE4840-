const imageInput = document.getElementById("image-input");
const preview = document.getElementById("preview");
const previewPlaceholder = document.getElementById("preview-placeholder");
const processedPreview = document.getElementById("processed-preview");
const processedPlaceholder = document.getElementById("processed-placeholder");
const runBtn = document.getElementById("run-btn");
const resetBtn = document.getElementById("reset-btn");
const startCameraBtn = document.getElementById("start-camera-btn");
const captureBtn = document.getElementById("capture-btn");
const cameraPreview = document.getElementById("camera-preview");
const cameraPlaceholder = document.getElementById("camera-placeholder");
const statusBox = document.getElementById("status-box");
const modelWarningBox = document.getElementById("model-warning");
const suiteBtn = document.getElementById("suite-btn");
const suiteSummary = document.getElementById("suite-summary");
const suiteTableWrap = document.getElementById("suite-table-wrap");
const suiteTableBody = document.getElementById("suite-table-body");
const correctLabel = document.getElementById("correct-label");
const feedbackNote = document.getElementById("feedback-note");
const saveFeedbackBtn = document.getElementById("save-feedback-btn");
const feedbackStatus = document.getElementById("feedback-status");
const preprocessModeSelect = document.getElementById("preprocess-mode");
const branchDiagnosticsBox = document.getElementById("branch-diagnostics");

let selectedFile = null;
let cameraStream = null;
let lastResult = null;
let currentPreviewUrl = null;

function setStatus(message, isError = false) {
  statusBox.textContent = message;
  statusBox.classList.toggle("error", isError);
}

function setModelWarning(message) {
  if (!message) {
    modelWarningBox.hidden = true;
    modelWarningBox.textContent = "";
    return;
  }
  modelWarningBox.hidden = false;
  modelWarningBox.textContent = message;
}

function resetResults() {
  lastResult = null;
  document.getElementById("predicted-class").textContent = "-";
  document.getElementById("cpu-predicted-class").textContent = "-";
  document.getElementById("cpu-time").textContent = "-";
  document.getElementById("fpga-time").textContent = "-";
  document.getElementById("fpga-rtl-time").textContent = "-";
  document.getElementById("speedup").textContent = "-";
  document.getElementById("timing-note").textContent =
    "FPGA RTL time is derived from on-chip cycle counters. Board wait time is the HPS-observed elapsed time.";
  document.getElementById("fpga-profile-meta").textContent = "Waiting for one run.";
  document.getElementById("profile-l1").textContent = "-";
  document.getElementById("profile-l2-p0").textContent = "-";
  document.getElementById("profile-l2-p1").textContent = "-";
  document.getElementById("profile-l3-p0").textContent = "-";
  document.getElementById("profile-l3-p1").textContent = "-";
  document.getElementById("profile-fc").textContent = "-";
  document.getElementById("profile-argmax").textContent = "-";
  document.getElementById("profile-total").textContent = "-";
  document.getElementById("cpu-bar").style.width = "0%";
  document.getElementById("fpga-bar").style.width = "0%";
  document.getElementById("cpu-bar-label").textContent = "-";
  document.getElementById("fpga-bar-label").textContent = "-";
  document.getElementById("cpu-top-class").textContent = "-";
  document.getElementById("cpu-confidence").textContent = "-";
  document.getElementById("cpu-margin").textContent = "-";
  document.getElementById("cpu-top-channels").textContent = "Top channels will appear after one run.";
  document.getElementById("confidence-note").textContent = "Waiting for one run.";
  document.getElementById("channel-grid").innerHTML = "";
  branchDiagnosticsBox.textContent = "Branch diagnostics will appear after one run.";
  processedPreview.removeAttribute("src");
  processedPreview.style.display = "none";
  processedPlaceholder.style.display = "grid";
  correctLabel.value = "";
  correctLabel.disabled = true;
  saveFeedbackBtn.disabled = true;
  feedbackStatus.textContent = "Run one inference first if you want to save a corrected sample.";
}

function renderBranchDiagnostics(rows, chosenMode) {
  if (!rows || rows.length === 0) {
    branchDiagnosticsBox.textContent = "Branch diagnostics unavailable.";
    return;
  }
  const parts = rows.map((row) => {
    const chosenTag = row.mode === chosenMode ? " [chosen]" : "";
    const topSummary = (row.top_channels || [])
      .slice(0, 2)
      .map((entry) => `${entry.label}:${entry.raw_score.toFixed(1)}`)
      .join(", ");
    return `${row.mode}: pred ${row.predicted_label}, margin ${row.margin.toFixed(1)}, top ${row.top_score.toFixed(1)}${topSummary ? `, leaders ${topSummary}` : ""}${chosenTag}`;
  });
  branchDiagnosticsBox.textContent = parts.join(" | ");
}

function renderCpuScoreReport(report) {
  if (!report) {
    document.getElementById("cpu-top-class").textContent = "-";
    document.getElementById("cpu-confidence").textContent = "-";
    document.getElementById("cpu-margin").textContent = "-";
    document.getElementById("cpu-top-channels").textContent = "Top channels will appear after one run.";
    document.getElementById("confidence-note").textContent = "Waiting for one run.";
    document.getElementById("channel-grid").innerHTML = "";
    return;
  }

  document.getElementById("cpu-top-class").textContent = report.predicted_label;
  document.getElementById("cpu-confidence").textContent = `${report.confidence_pct.toFixed(1)}%`;
  document.getElementById("cpu-margin").textContent = report.margin.toFixed(1);
  document.getElementById("confidence-note").textContent = report.note || "";

  const topSummary = (report.top_channels || [])
    .map((entry) => `${entry.label}: raw ${entry.raw_score.toFixed(1)}, conf ${entry.probability_pct.toFixed(1)}%`)
    .join(" | ");
  document.getElementById("cpu-top-channels").textContent =
    topSummary || "Top channels unavailable.";

  const grid = document.getElementById("channel-grid");
  grid.innerHTML = "";
  for (const channel of report.channels || []) {
    const row = document.createElement("div");
    row.className = "channel-row";
    row.innerHTML = `
      <span class="channel-label">${channel.label}</span>
      <div class="channel-track"><div class="channel-fill" style="width:${channel.probability_pct.toFixed(2)}%"></div></div>
      <span class="channel-score">${channel.raw_score.toFixed(1)}</span>
      <span class="channel-prob">${channel.probability_pct.toFixed(1)}%</span>
    `;
    grid.appendChild(row);
  }
}

function formatProfileRow(stage) {
  if (!stage) {
    return "-";
  }
  const timeUs =
    stage.time_us < 0.1 ? stage.time_us.toFixed(2) :
    stage.time_us < 1 ? stage.time_us.toFixed(2) :
    stage.time_us.toFixed(1);
  return `${stage.cycles} cyc / ${timeUs} us`;
}

function renderProfile(profile) {
  if (!profile) {
    return;
  }
  const stageByLabel = Object.fromEntries(profile.stages.map((stage) => [stage.label, stage]));
  document.getElementById("fpga-profile-meta").textContent =
    `${profile.fabric_mhz.toFixed(2)} MHz fabric clock`;
  document.getElementById("profile-l1").textContent = formatProfileRow(stageByLabel["L1"]);
  document.getElementById("profile-l2-p0").textContent = formatProfileRow(stageByLabel["L2 P0"]);
  document.getElementById("profile-l2-p1").textContent = formatProfileRow(stageByLabel["L2 P1"]);
  document.getElementById("profile-l3-p0").textContent = formatProfileRow(stageByLabel["L3 P0"]);
  document.getElementById("profile-l3-p1").textContent = formatProfileRow(stageByLabel["L3 P1"]);
  document.getElementById("profile-fc").textContent = formatProfileRow(stageByLabel["FC"]);
  document.getElementById("profile-argmax").textContent = formatProfileRow(stageByLabel["Argmax"]);
  document.getElementById("profile-total").textContent =
    `${profile.total_cycles} cyc / ${profile.rtl_time_us.toFixed(1)} us`;
}

function setPreviewSource(url) {
  if (currentPreviewUrl && currentPreviewUrl.startsWith("blob:")) {
    URL.revokeObjectURL(currentPreviewUrl);
  }
  currentPreviewUrl = url;
  preview.src = url;
  preview.style.display = "block";
  previewPlaceholder.style.display = "none";
}

async function startCamera() {
  if (cameraStream) {
    return;
  }
  const stream = await navigator.mediaDevices.getUserMedia({
    video: {
      facingMode: "user",
      width: { ideal: 960 },
      height: { ideal: 960 },
    },
    audio: false,
  });
  cameraStream = stream;
  cameraPreview.srcObject = stream;
  cameraPreview.style.display = "block";
  cameraPlaceholder.style.display = "none";
  captureBtn.disabled = false;
  startCameraBtn.textContent = "Camera Ready";
  startCameraBtn.disabled = true;
}

async function captureFrame() {
  if (!cameraStream) {
    return;
  }
  const width = cameraPreview.videoWidth || 640;
  const height = cameraPreview.videoHeight || 640;
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  context.drawImage(cameraPreview, 0, 0, width, height);
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/png"));
  if (!blob) {
    throw new Error("Failed to capture webcam frame");
  }
  selectedFile = new File([blob], "webcam_capture.png", { type: "image/png" });
  imageInput.value = "";
  resetResults();
  setPreviewSource(URL.createObjectURL(selectedFile));
  runBtn.disabled = false;
  setStatus("Webcam frame captured. Run comparison when you are ready.");
}

function renderSuite(payload) {
  suiteSummary.textContent = `Built-in suite: ${payload.passed}/${payload.total} passed.`;
  suiteTableBody.innerHTML = "";
  for (const row of payload.rows) {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${row.case}</td>
      <td>${row.expected_class}</td>
      <td>${row.cpu_predicted_class}</td>
      <td>${row.fpga_predicted_class}</td>
      <td class="${row.pass ? "suite-pass" : "suite-fail"}">${row.pass ? "PASS" : "FAIL"}</td>
    `;
    suiteTableBody.appendChild(tr);
  }
  suiteTableWrap.hidden = false;
}

function renderChart(cpuMs, fpgaMs) {
  const maxValue = Math.max(cpuMs, fpgaMs, 1);
  const cpuWidth = (cpuMs / maxValue) * 100;
  const fpgaWidth = (fpgaMs / maxValue) * 100;
  document.getElementById("cpu-bar").style.width = `${cpuWidth}%`;
  document.getElementById("fpga-bar").style.width = `${fpgaWidth}%`;
  document.getElementById("cpu-bar-label").textContent = `${cpuMs.toFixed(2)} ms`;
  document.getElementById("fpga-bar-label").textContent = `${fpgaMs.toFixed(2)} ms`;
}

async function loadHealth() {
  try {
    const response = await fetch("/api/health");
    const payload = await response.json();
    if (response.ok) {
      setModelWarning(payload.model_warning || "");
    }
  } catch {
    // Keep the page usable even if health probing fails.
  }
}

imageInput.addEventListener("change", () => {
  const [file] = imageInput.files;
  selectedFile = file || null;
  resetResults();

  if (!selectedFile) {
    preview.removeAttribute("src");
    preview.style.display = "none";
    previewPlaceholder.style.display = "grid";
    runBtn.disabled = true;
    setStatus("Waiting for an upload.");
    return;
  }

  setPreviewSource(URL.createObjectURL(selectedFile));
  runBtn.disabled = false;
  setStatus("Image ready. Run comparison when you are ready.");
});

resetBtn.addEventListener("click", () => {
  imageInput.value = "";
  selectedFile = null;
  preview.removeAttribute("src");
  preview.style.display = "none";
  previewPlaceholder.style.display = "grid";
  runBtn.disabled = true;
  resetResults();
  setStatus("Waiting for an upload.");
});

startCameraBtn.addEventListener("click", async () => {
  try {
    await startCamera();
    setStatus("Camera ready. Capture a frame when you are ready.");
  } catch (error) {
    setStatus(error.message || "Unable to start webcam.", true);
  }
});

captureBtn.addEventListener("click", async () => {
  try {
    await captureFrame();
  } catch (error) {
    setStatus(error.message || "Unable to capture webcam frame.", true);
  }
});

runBtn.addEventListener("click", async () => {
  if (!selectedFile) {
    return;
  }

  runBtn.disabled = true;
  setStatus("Running CPU and FPGA inference...");

  const formData = new FormData();
  formData.append("image", selectedFile);
  formData.append("preprocess_mode", preprocessModeSelect.value);

  try {
    const response = await fetch("/api/infer", {
      method: "POST",
      body: formData,
    });
    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload.error || "Inference failed");
    }

    lastResult = payload;
    document.getElementById("predicted-class").textContent = payload.predicted_label;
    document.getElementById("cpu-predicted-class").textContent = payload.cpu_predicted_label;
    document.getElementById("cpu-time").textContent = `${payload.cpu_time_ms.toFixed(2)} ms`;
    document.getElementById("fpga-time").textContent = `${payload.fpga_time_ms.toFixed(2)} ms`;
    document.getElementById("fpga-rtl-time").textContent = `${payload.fpga_rtl_time_ms.toFixed(3)} ms`;
    document.getElementById("speedup").textContent =
      payload.speedup ? `${payload.speedup.toFixed(2)}x` : "-";
    document.getElementById("timing-note").textContent =
      `RTL ${payload.fpga_rtl_time_us.toFixed(1)} us from on-chip counters. ` +
      `Board wait ${payload.fpga_time_ms.toFixed(2)} ms. Remote request ${payload.fpga_request_time_ms.toFixed(2)} ms. ` +
      `Board total ${payload.fpga_board_total_time_ms.toFixed(2)} ms, load ${payload.fpga_board_case_load_time_ms.toFixed(2)} ms, program ${payload.fpga_board_program_time_ms.toFixed(2)} ms.`;

    renderChart(payload.cpu_time_ms, payload.fpga_time_ms);
    renderProfile(payload.fpga_profile);
    renderBranchDiagnostics(payload.branch_diagnostics, payload.preprocess_mode);
    renderCpuScoreReport(payload.cpu_score_report);
    if (payload.preprocessed_preview_url) {
      processedPreview.src = payload.preprocessed_preview_url;
      processedPreview.style.display = "block";
      processedPlaceholder.style.display = "none";
    }
    correctLabel.disabled = false;
    saveFeedbackBtn.disabled = false;
    feedbackStatus.textContent = "If this result is wrong, select the correct label and save the sample for retraining.";
    setModelWarning(payload.model_warning || "");
    const preprocessMode = payload.preprocess_mode ? ` Preprocess: ${payload.preprocess_mode}.` : "";
    setStatus(`Done. Board CPU predicted gesture ID ${payload.cpu_predicted_label}, FPGA predicted gesture ID ${payload.predicted_label}.${preprocessMode}`);
  } catch (error) {
    setStatus(error.message, true);
  } finally {
    runBtn.disabled = false;
  }
});

saveFeedbackBtn.addEventListener("click", async () => {
  if (!selectedFile || !lastResult) {
    feedbackStatus.textContent = "Run one inference before saving feedback.";
    return;
  }
  if (!correctLabel.value) {
    feedbackStatus.textContent = "Choose the correct gesture ID first.";
    return;
  }

  saveFeedbackBtn.disabled = true;
  feedbackStatus.textContent = "Saving correction sample...";
  const formData = new FormData();
  formData.append("image", selectedFile);
  formData.append("corrected_label", correctLabel.value);
  formData.append("predicted_label", String(lastResult.predicted_label));
  formData.append("preprocess_mode", String(lastResult.preprocess_mode || ""));
  formData.append("note", feedbackNote.value || "");

  try {
    const response = await fetch("/api/feedback", {
      method: "POST",
      body: formData,
    });
    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload.error || "Unable to save correction sample");
    }
    feedbackStatus.textContent = `Saved correction sample ${payload.sample_id} under ${payload.saved_dir}.`;
  } catch (error) {
    feedbackStatus.textContent = error.message;
  } finally {
    saveFeedbackBtn.disabled = false;
  }
});

suiteBtn.addEventListener("click", async () => {
  suiteBtn.disabled = true;
  suiteSummary.textContent = "Running built-in suite...";
  try {
    const response = await fetch("/api/sample-suite");
    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload.error || "Suite failed");
    }
    renderSuite(payload);
  } catch (error) {
    suiteSummary.textContent = error.message;
    suiteTableWrap.hidden = true;
  } finally {
    suiteBtn.disabled = false;
  }
});

loadHealth();
