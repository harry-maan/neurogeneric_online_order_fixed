(function () {
  "use strict";
  let recognition = null;
  let lastTranscript = "";
  window.startVoice = function () {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    const status = document.getElementById("voice_status");
    if (!SpeechRecognition) {
      if (status) status.textContent = " Voice input is not supported in this browser. Try Chrome or type the medicine name.";
      return;
    }
    if (recognition) { try { recognition.stop(); } catch (_) {} }
    recognition = new SpeechRecognition();
    recognition.lang = document.documentElement.lang || "en-IN";
    recognition.continuous = false;
    recognition.interimResults = false;
    recognition.maxAlternatives = 4;
    lastTranscript = "";
    if (status) status.textContent = " Listening… say the medicine name and strength.";
    recognition.onresult = function (event) {
      const result = event.results[event.results.length - 1];
      const transcript = (result[0] && result[0].transcript || "").trim();
      if (!transcript || transcript === lastTranscript) return;
      lastTranscript = transcript;
      if (window.Shiny) Shiny.setInputValue("voice_text", transcript, {priority: "event"});
      if (status) status.textContent = " Heard: “" + transcript + "” — check the text, then Detect medicines.";
    };
    recognition.onerror = function (event) {
      if (status) status.textContent = " Voice error: " + event.error + ". You can type the medicine name instead.";
    };
    recognition.onend = function () {
      if (status && status.textContent.indexOf("Heard:") !== 0 &&
          status.textContent.indexOf("Voice error:") !== 0) status.textContent = " Listening stopped.";
    };
    try { recognition.start(); } catch (e) {
      if (status) status.textContent = " Could not start microphone. Check browser permission and use HTTPS or localhost.";
    }
  };

  window.getGPS = function () {
    const status = document.getElementById("loc_text");
    if (!navigator.geolocation) {
      if (window.Shiny) Shiny.setInputValue("gps_error", "This browser does not support location", {priority: "event"});
      return;
    }
    if (status) status.textContent = "Requesting location permission…";
    navigator.geolocation.getCurrentPosition(function (pos) {
      if (window.Shiny) Shiny.setInputValue("gps", {
        lat: pos.coords.latitude, lon: pos.coords.longitude,
        accuracy: pos.coords.accuracy
      }, {priority: "event"});
    }, function (err) {
      if (window.Shiny) Shiny.setInputValue("gps_error", err.message || "Permission denied", {priority: "event"});
    }, {enableHighAccuracy: true, timeout: 12000, maximumAge: 60000});
  };
})();
