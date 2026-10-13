# NeuroGeneric Finder - prototype (SYNTHETIC DATA).
options(shiny.maxRequestSize = 50 * 1024^2)
suppressPackageStartupMessages({ library(shiny); library(bslib); library(DT) })
source("R/config.R"); source("R/helpers.R")
if (!file.exists("data/drugs.csv")) source("R/00_generate_data.R")      # self-heals: regenerates identical data

drugs  <- read.csv("data/drugs.csv", stringsAsFactors = FALSE)
stores <- read.csv("data/stores.csv", stringsAsFactors = FALSE)
inv    <- read.csv("data/inventory.csv", stringsAsFactors = FALSE)
safety <- read.csv("data/safety.csv", stringsAsFactors = FALSE)
ddi    <- read.csv("data/interactions.csv", stringsAsFactors = FALSE)
fda    <- if (file.exists("data/openfda_labels.csv")) read.csv("data/openfda_labels.csv", stringsAsFactors = FALSE) else NULL
aliases   <- build_aliases(drugs)
areas     <- unique(stores[, c("area", "lat", "lon")])
has_leaf  <- requireNamespace("leaflet", quietly = TRUE)
has_ocr   <- requireNamespace("tesseract", quietly = TRUE) && requireNamespace("magick", quietly = TRUE)
drug_label <- function(id) { d <- drugs[drugs$drug_id == id, ]; paste0(d$brand_name, " (", d$generic_name, " ", d$strength, ")") }
DEMO_RX <- "Rx  Dr. A. Sharma, Neurology OPD\nPt: Demo Patient  Age 58\n1. Tab Keppra 500 mg  1-0-1\n2. Tab Lamictal 100 mg  1-0-1\n3. Tab Sinemet 100/25  1-1-1\nReview after 4 weeks"

ui <- page_navbar(
  title = "NeuroGeneric Finder", id = "tabs", theme = bs_theme(version = 5, primary = "#0b6e99"),
  header = tags$head(tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
                     tags$link(rel = "stylesheet", href = "style.css"), tags$script(src = "app.js"),
                     tags$style(HTML(".navbar .navbar-nav{display:flex;flex-wrap:wrap;align-items:center}.navbar .navbar-nav .nav-link{white-space:nowrap}@media(max-width:767px){.navbar .navbar-nav{flex-wrap:nowrap;overflow-x:auto;max-width:100%;-webkit-overflow-scrolling:touch}.navbar .navbar-nav .nav-link{font-size:.82rem;padding:.5rem .45rem}}"))),
  collapsible = FALSE,
  nav_panel("Scan", value = "scan", icon = icon("camera"),
    card(card_header("1 \u00b7 Prescription input"),
      fileInput("rx_img", NULL, accept = "image/*", capture = "environment", buttonLabel = "\U0001F4F7 Photo / upload", placeholder = "Take or choose a prescription image", width = "100%"),
      uiOutput("blur_msg"),
      tags$button(type = "button", class = "btn btn-outline-primary btn-lg-touch", onclick = "startVoice()", "\U0001F3A4 Speak drug names"),
      tags$span(id = "voice_status", ""),
      textAreaInput("rx_text", "Detected / typed text (editable)", rows = 5, width = "100%", placeholder = "OCR text, voice text or type here"),
      actionButton("load_demo", "Load demo prescription", class = "btn btn-link"),
      checkboxInput("use_llm", "Also use LLM to read messy text (sends text only; needs ANTHROPIC_API_KEY)", FALSE),
      actionButton("detect", "Detect medicines", class = "btn btn-primary btn-lg-touch")),
    card(card_header("2 \u00b7 Confirm medicines & packs"), uiOutput("detected_ui"), uiOutput("qty_ui")),
    card(card_header("3 \u00b7 Your location"),
      tags$button(type = "button", class = "btn btn-outline-secondary btn-lg-touch", onclick = "getGPS()", "\U0001F4CD Use my GPS"),
      selectInput("area_pick", "...or choose area (demo)", choices = areas$area, selected = "C-Scheme", width = "100%"),
      textOutput("loc_text")),
    div(class = "d-flex flex-wrap gap-2",
      actionButton("go_stores", "Find nearest stores \u2192", class = "btn btn-success btn-lg-touch"),
      actionButton("open_order_tab", "Online order", class = "btn btn-primary btn-lg-touch"))),

  nav_panel("Stores & savings", value = "stores", icon = icon("store"),
    uiOutput("kpis"),
    card(card_header("Nearest stores with generics"), if (has_leaf) leaflet::leafletOutput("map", height = "520px") else p("Install 'leaflet' for the map."),
         DTOutput("store_tbl")),
    card(card_header("Basket at selected store"), uiOutput("store_pick_ui"), DTOutput("basket_tbl"),
         uiOutput("store_recommendation_note"),
         actionButton("proceed_order", "Proceed to home-delivery order →", class = "btn btn-success btn-lg-touch"),
         p(class = "disclaimer", "Prices/stock are synthetic demo data. Distance is straight-line, not road distance."))),

  nav_panel("Safety", value = "safety", icon = icon("shield-halved"),
    card(card_header("Unlock after talking to a professional"),
      radioButtons("consult", "I have discussed these medicines with my:", c("Not yet" = "none", "Pharmacist" = "pharmacist", "Doctor" = "doctor")),
      checkboxInput("consult_ack", "I understand this is information only and does not replace medical advice.", FALSE)),
    uiOutput("safety_ui")),

  nav_panel("Online order", value = "order", icon = icon("truck"),
    card(card_header("1 · Choose medicine preference"),
      div(class = "alert alert-info",
          strong("No rescan needed: "),
          "This tab uses the medicines detected and confirmed on the Scan tab, including pack quantities and the selected store. Change the list only on the Scan tab."),
      radioButtons("order_preference", "Which medicines should we price?",
        choices = c("Generic medicines" = "generic",
                    "Branded medicines" = "branded",
                    "Either available (compare both)" = "either"),
        selected = "generic", inline = FALSE),
      uiOutput("order_basket_preview")),
    card(card_header("2 · Complete home-delivery address"),
      textInput("order_patient_name", "Patient / customer name", placeholder = "Full name"),
      textInput("order_phone", "Mobile number", placeholder = "10-digit mobile number"),
      textInput("order_address1", "House / flat / building and street", placeholder = "House number, building, street"),
      textInput("order_address2", "Area / locality / landmark", placeholder = "Area, locality, landmark (optional)"),
      textInput("order_city", "City / town", placeholder = "City"),
      textInput("order_state", "State", value = "Rajasthan"),
      textInput("order_pincode", "PIN code", placeholder = "6-digit PIN code"),
      textAreaInput("order_notes", "Delivery notes (optional)", rows = 2),
      checkboxInput("order_consent",
        "I agree to prepare this demo request using the details entered. I understand it is not sent to a pharmacy and prices/stock are not live.", FALSE)),
    card(card_header("3 · Final bill and branded-vs-generic comparison"),
      p("Bill includes an illustrative 5% GST and ₹40 delivery charge. These are demo assumptions and must be replaced with verified tax and delivery rules before real orders."),
      DTOutput("order_bill_tbl"),
      actionButton("prepare_order", "Generate final bill / order request", class = "btn btn-primary btn-lg-touch"),
      uiOutput("order_request_summary"))
  ))

server <- function(input, output, session) {
  detected <- reactiveVal(.empty_match())
  qty_store <- reactiveValues()

  # ---- inputs: image (blur gate -> OCR), voice, demo text ----
  observeEvent(input$rx_img, {
    f <- input$rx_img$datapath
    res <- tryCatch(is_blurry(f), error = function(e) { showNotification(paste("Image check failed:", e$message), type = "error"); NULL })
    if (is.null(res)) return()
    output$blur_msg <- renderUI(if (res$blurry) div(class = "alert alert-danger", sprintf("Image looks blurry (sharpness %.0f < %d). Hold steady, add light, retake.", res$score, BLUR_THRESHOLD))
                                else div(class = "alert alert-success", sprintf("Image is clear (sharpness %.0f).", res$score)))
    if (res$blurry) return()
    if (!has_ocr) { showNotification("OCR package 'tesseract' not installed - type or speak instead.", type = "warning"); return() }
    withProgress(message = "Reading prescription...", value = 0.5, {
      txt <- tryCatch(ocr_image(f), error = function(e) { showNotification(e$message, type = "error"); "" })
      updateTextAreaInput(session, "rx_text", value = txt)
    })
  })
  # Speech results are appended on a new line, without the literal "NULL" or
  # duplicated whitespace. The user can edit the transcript before matching.
  observeEvent(input$voice_text, {
    spoken <- trimws(input$voice_text %||% "")
    if (!nzchar(spoken)) return()
    existing <- trimws(input$rx_text %||% "")
    combined <- if (!nzchar(existing)) spoken else paste(existing, spoken, sep = "\n")
    updateTextAreaInput(session, "rx_text", value = combined)
  }, ignoreInit = TRUE)
  observeEvent(input$load_demo, updateTextAreaInput(session, "rx_text", value = DEMO_RX))

  # ---- detect ----
  observeEvent(input$detect, {
    withProgress(message = "Matching medicines...", value = 0.5, {
      detected(detect_drugs(input$rx_text, aliases, MATCH_THRESHOLD, isTRUE(input$use_llm)))
    })
    if (!nrow(detected())) showNotification("No catalogue medicines found. Edit the text and retry.", type = "warning")
  })
  output$detected_ui <- renderUI({
    d <- detected(); if (!nrow(d)) return(p(class = "text-muted", "Nothing detected yet."))
    ch <- setNames(d$drug_id, paste0(vapply(d$drug_id, drug_label, ""), ifelse(d$score < 0.95, "  \u26a0 check spelling", "")))
    checkboxGroupInput("sel_drugs", "Untick anything that is wrong:", choices = ch, selected = d$drug_id, width = "100%")
  })
  output$qty_ui <- renderUI({
    ids <- input$sel_drugs; if (!length(ids)) return(NULL)
    tagList(lapply(ids, function(id) numericInput(paste0("qty_", id), paste("Packs of", drugs$brand_name[drugs$drug_id == id]),
                                                  value = isolate(input[[paste0("qty_", id)]]) %||% 1, min = 1, max = 12, width = "100%")))
  })
  qty <- reactive({ ids <- input$sel_drugs %||% character(); setNames(vapply(ids, function(i) as.numeric(input[[paste0("qty_", i)]] %||% 1), 0), ids) })

  # ---- location ----
  observeEvent(input$gps_error, showNotification(paste("GPS unavailable:", input$gps_error, "- using chosen area."), type = "warning"))
  loc <- reactive({
    if (!is.null(input$gps)) list(lat = input$gps$lat, lon = input$gps$lon, src = "GPS")
    else { a <- areas[areas$area == input$area_pick, ]; list(lat = a$lat[1] %||% DEFAULT_LAT, lon = a$lon[1] %||% DEFAULT_LON, src = paste("area:", input$area_pick)) }
  })
  output$loc_text <- renderText(sprintf("Using %s (%.4f, %.4f)", loc()$src, loc()$lat, loc()$lon))
  observeEvent(input$go_stores, {
    if (!length(input$sel_drugs)) showNotification("Detect and confirm at least one medicine first.", type = "warning")
    else nav_select("tabs", "stores")
  })
  observeEvent(input$open_order_tab, {
    if (!length(input$sel_drugs)) {
      showNotification("First detect and confirm medicines on the Scan tab. The order tab will reuse them.", type = "warning")
      return()
    }
    nav_select("tabs", "order")
  })
  observeEvent(input$proceed_order, {
    if (!length(input$sel_drugs)) {
      showNotification("Go to Scan and detect/confirm medicines first.", type = "warning")
      return()
    }
    if (is.null(chosen_store())) {
      showNotification("No store basket is available yet. Check the Scan selections.", type = "warning")
      return()
    }
    nav_select("tabs", "order")
  })

  # ---- ranking + savings (deterministic; the LLM never picks stores or prices) ----
  ranked <- reactive({ req(length(input$sel_drugs) > 0); rank_stores(inv, stores, drugs, input$sel_drugs, qty(), loc()$lat, loc()$lon) })

  # Prefer stores that can fill the whole basket. Among fully stocked stores,
  # select the lowest preference-matched total, then shortest distance. If no
  # store has every medicine, maximize availability first.
  recommended_store <- reactive({
    r <- ranked()
    if (!nrow(r)) return(NULL)
    pref <- input$order_preference %||% "generic"
    totals <- vapply(r$store_id, function(sid) {
      b <- store_basket(inv, drugs, sid, input$sel_drugs, qty())
      ok <- b[b$buyable, , drop = FALSE]
      if (!nrow(ok)) return(Inf)
      if (identical(pref, "branded")) sum(ok$brand_total, na.rm = TRUE) else sum(ok$generic_total, na.rm = TRUE)
    }, numeric(1))
    r$basket_total <- totals
    r$fully_available <- r$n_available >= r$n_requested
    r <- r[order(!r$fully_available, -r$n_available, r$basket_total, r$distance_km), , drop = FALSE]
    r$store_id[1]
  })
  chosen_store <- reactive({
    r <- ranked()
    if (!nrow(r)) return(NULL)
    if (!is.null(input$store_pick) && input$store_pick %in% r$store_id) input$store_pick else recommended_store()
  })
  basket <- reactive({ req(length(input$sel_drugs) > 0, !is.null(chosen_store())); store_basket(inv, drugs, chosen_store(), input$sel_drugs, qty()) })

  observeEvent(list(input$sel_drugs, qty(), loc(), input$order_preference), {
    if (!length(input$sel_drugs)) return()
    r <- ranked()
    if (nrow(r)) updateSelectInput(session, "store_pick", selected = recommended_store())
  }, ignoreInit = TRUE)

  output$store_pick_ui <- renderUI({
    if (!length(input$sel_drugs)) return(p("Detect and confirm medicines on the Scan tab first."))
    r <- ranked()
    labels <- paste0(r$store_name, " — ", round(r$distance_km, 1), " km · ", r$n_available, "/", r$n_requested, " available")
    selectInput("store_pick", "Store (recommended: full stock, lowest total, then nearest)",
      choices = setNames(r$store_id, labels), selected = recommended_store(), width = "100%")
  })

  output$store_recommendation_note <- renderUI({
    if (!length(input$sel_drugs)) return(NULL)
    r <- ranked(); s <- r[r$store_id == chosen_store(), , drop = FALSE]
    if (!nrow(s)) return(NULL)
    b <- basket(); available <- sum(b$buyable, na.rm = TRUE)
    total_col <- if (identical(input$order_preference, "branded")) "brand_total" else "generic_total"
    total <- sum(b[[total_col]][b$buyable], na.rm = TRUE)
    div(class = "alert alert-info", strong("Store summary: "), s$store_name[1],
      " · ", available, "/", nrow(b), " requested medicines available · estimated ",
      if (identical(input$order_preference, "branded")) "branded" else "generic", " total ", inr(total),
      if (available < nrow(b)) " · Some medicines are unavailable here; review the basket before proceeding." else " · All requested medicines are in stock in this demo data.")
  })
  output$kpis <- renderUI({
    if (!length(input$sel_drugs)) return(card(p("Go to Scan, detect medicines, then come back.")))
    b <- basket(); r <- ranked(); s <- r[r$store_id == chosen_store(), ]
    ok <- b[b$buyable, ]
    layout_columns(col_widths = c(6, 6, 6, 6),
      value_box("Store", s$store_name, p(sprintf("%.1f km \u00b7 %s", s$distance_km, s$open_hours)), theme = "primary"),
      value_box("Generic total", inr(sum(ok$generic_total)), p(sprintf("%d of %d medicines available", nrow(ok), nrow(b))), theme = "success"),
      value_box("Branded total", inr(sum(ok$brand_total)), p("same medicines, branded MRP"), theme = "secondary"),
      value_box("You save", inr(sum(ok$saving)), p(sprintf("%.0f%% cheaper", ifelse(sum(ok$brand_total) > 0, 100 * sum(ok$saving) / sum(ok$brand_total), 0))), theme = "warning"))
  })
  output$store_tbl <- renderDT({
    r <- ranked(); datatable(transform(r[, c("store_name", "distance_km", "n_available", "n_requested", "generic_cost", "saving")],
      generic_cost = round(generic_cost), saving = round(saving)),
      colnames = c("Store", "km", "Available", "Requested", "Generic \u20b9", "Saving \u20b9"), rownames = FALSE, selection = "none",
      options = list(dom = "tp", pageLength = 5, scrollX = TRUE))
  })
  output$basket_tbl <- renderDT({
    b <- basket(); datatable(b[, c("brand_name", "generic_name", "packs", "status", "generic_price_inr", "brand_mrp_inr", "saving")],
      colnames = c("Brand", "Generic", "Packs", "Stock", "Generic \u20b9/pack", "Brand \u20b9/pack", "Saving \u20b9"), rownames = FALSE, selection = "none",
      options = list(dom = "t", scrollX = TRUE)) |> formatRound(c("generic_price_inr", "brand_mrp_inr", "saving"), 0)
  })
  if (has_leaf) output$map <- leaflet::renderLeaflet({
    r <- ranked(); l <- loc()
    r$marker_colour <- ifelse(r$n_available == r$n_requested, "#198754",
                              ifelse(r$n_available > 0, "#fd7e14", "#dc3545"))
    r$popup_html <- sprintf(
      "<div class='store-popup'><strong>%s</strong><br>Distance: %.1f km<br>Available: %d / %d medicines<br>Estimated generic basket: %s<br>Potential saving: %s<br><small>%s</small></div>",
      htmltools::htmlEscape(r$store_name), r$distance_km, r$n_available, r$n_requested,
      htmltools::htmlEscape(inr(r$generic_cost)), htmltools::htmlEscape(inr(r$saving)),
      htmltools::htmlEscape(r$open_hours))
    m <- leaflet::leaflet(r, options = leaflet::leafletOptions(zoomControl = TRUE)) |>
      leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron) |>
      leaflet::addCircleMarkers(lng = ~lon, lat = ~lat, radius = 9,
        stroke = TRUE, weight = 2, color = ~marker_colour, fillColor = ~marker_colour,
        fillOpacity = 0.88, label = ~paste0(store_name, " · ", round(distance_km, 1), " km"),
        popup = ~popup_html, popupOptions = leaflet::popupOptions(maxWidth = 280)) |>
      leaflet::addMarkers(lng = l$lon, lat = l$lat, label = "Your selected location",
                          popup = "Your location / selected area") |>
      leaflet::addScaleBar(position = "bottomleft") |>
      leaflet::addLegend(position = "topright", colors = c("#198754", "#fd7e14", "#dc3545"),
        labels = c("All requested medicines", "Some available", "None available"),
        title = "Stock at store", opacity = 0.9)
    if (nrow(r) > 0) {
      bounds <- c(min(c(r$lon, l$lon), na.rm = TRUE), min(c(r$lat, l$lat), na.rm = TRUE),
                  max(c(r$lon, l$lon), na.rm = TRUE), max(c(r$lat, l$lat), na.rm = TRUE))
      m <- m |> leaflet::fitBounds(bounds[1], bounds[2], bounds[3], bounds[4])
    } else m <- m |> leaflet::setView(l$lon, l$lat, 13)
    m
  })

  # ---- online order: reuses Scan-tab selections; demo bill only ----
  order_request <- reactiveVal(NULL)
  GST_RATE <- 0.05
  DELIVERY_CHARGE <- 40

  order_basket <- reactive({
    ids <- input$sel_drugs %||% character()
    if (!length(ids)) return(data.frame())
    sid <- chosen_store()
    if (is.null(sid)) return(data.frame())
    store_basket(inv, drugs, sid, ids, qty()[ids])
  })

  order_bill <- reactive({
    b <- order_basket()
    if (!nrow(b)) return(data.frame())
    pref <- input$order_preference %||% "generic"
    b$generic_line_total <- ifelse(b$buyable, b$generic_total, NA_real_)
    b$branded_line_total <- ifelse(b$buyable, b$brand_total, NA_real_)
    b$chosen_option <- ifelse(!b$buyable, "Unavailable",
      if (pref == "generic") "Generic" else if (pref == "branded") "Branded" else
        ifelse(b$generic_total <= b$brand_total, "Generic (lower cost)", "Branded (lower cost)"))
    b$chosen_line_total <- ifelse(!b$buyable, NA_real_,
      if (pref == "generic") b$generic_total else if (pref == "branded") b$brand_total else pmin(b$generic_total, b$brand_total))
    b
  })

  output$order_basket_preview <- renderUI({
    ids <- input$sel_drugs %||% character()
    if (!length(ids)) return(div(class = "alert alert-warning", "No confirmed medicines found yet. Go to the Scan tab once, detect the prescription, and confirm the medicines."))
    b <- order_basket()
    r <- ranked(); s <- r[r$store_id == chosen_store(), , drop = FALSE]
    div(class = "card card-body mb-3",
      h5("Medicines carried over from Scan"),
      p(strong("Selected store: "), if (nrow(s)) s$store_name[1] else "Not selected"),
      p(strong("Stock availability: "), sum(b$buyable, na.rm = TRUE), "/", nrow(b), " items available"),
      p("Medicine names, strengths and quantities are inherited from the Scan tab; no second prescription upload is required."),
      if (sum(b$buyable, na.rm = TRUE) < nrow(b)) p(class = "text-warning", "Some items are unavailable at this demo store and are excluded from the payable estimate."),
      p(class = "small text-muted", "Stock and prices are synthetic demo data, not live pharmacy confirmation."))
  })

  output$order_bill_tbl <- renderDT({
    b <- order_bill()
    if (!nrow(b)) return(datatable(data.frame(Message = "Detect and confirm medicines on the Scan tab first."), options = list(dom = "t"), rownames = FALSE))
    pref <- input$order_preference %||% "generic"
    generic_sub <- sum(b$generic_line_total, na.rm = TRUE)
    brand_sub <- sum(b$branded_line_total, na.rm = TRUE)
    chosen_sub <- sum(b$chosen_line_total, na.rm = TRUE)
    chosen_gst <- round(chosen_sub * GST_RATE, 2)
    generic_gst <- round(generic_sub * GST_RATE, 2)
    brand_gst <- round(brand_sub * GST_RATE, 2)
    delivery <- if (is.finite(chosen_sub) && chosen_sub > 0) DELIVERY_CHARGE else 0
    chosen_total <- chosen_sub + chosen_gst + delivery
    generic_total <- generic_sub + generic_gst + if (generic_sub > 0) DELIVERY_CHARGE else 0
    brand_total <- brand_sub + brand_gst + if (brand_sub > 0) DELIVERY_CHARGE else 0
    detail <- data.frame(
      Medicine = paste0(b$brand_name, " / ", b$generic_name),
      Packs = b$packs,
      Availability = ifelse(b$buyable, "Available", "Unavailable"),
      `Generic price (₹)` = round(b$generic_line_total, 2),
      `Branded price (₹)` = round(b$branded_line_total, 2),
      `Selected option` = b$chosen_option,
      `Selected line total (₹)` = round(b$chosen_line_total, 2),
      check.names = FALSE
    )
    summary <- data.frame(
      Medicine = c("SUBTOTAL", "GST (illustrative 5%)", "Home delivery (demo)", "FINAL ESTIMATED BILL", "COMPARISON — GENERIC incl. GST + delivery", "COMPARISON — BRANDED incl. GST + delivery"),
      Packs = rep(NA_integer_, 6), Availability = rep("—", 6),
      `Generic price (₹)` = c(round(generic_sub,2), round(generic_gst,2), if (generic_sub > 0) DELIVERY_CHARGE else 0, NA, NA, NA),
      `Branded price (₹)` = c(round(brand_sub,2), round(brand_gst,2), if (brand_sub > 0) DELIVERY_CHARGE else 0, NA, NA, NA),
      `Selected option` = c("", "", "", if (pref == "either") "Either: lower available option per item" else if (pref == "branded") "Branded" else "Generic", "", ""),
      `Selected line total (₹)` = c(round(chosen_sub,2), chosen_gst, delivery, round(chosen_total,2), round(generic_total,2), round(brand_total,2)),
      check.names = FALSE
    )
    datatable(rbind(detail, summary), rownames = FALSE, selection = "none",
      options = list(dom = "t", scrollX = TRUE, pageLength = 20),
      caption = htmltools::tags$caption(style = "caption-side: top; text-align:left;", "Estimated bill in INR. Unavailable items are excluded; GST and delivery are demo assumptions.")) |>
      formatRound(columns = c("Generic price (₹)", "Branded price (₹)", "Selected line total (₹)"), digits = 2)
  })

  observeEvent(input$prepare_order, {
    order_request(NULL)
    nm <- trimws(input$order_patient_name %||% "")
    phone <- gsub("[^0-9]", "", input$order_phone %||% "")
    addr1 <- trimws(input$order_address1 %||% "")
    addr2 <- trimws(input$order_address2 %||% "")
    city <- trimws(input$order_city %||% "")
    state <- trimws(input$order_state %||% "")
    pin <- gsub("[^0-9]", "", input$order_pincode %||% "")
    selected_ids <- input$sel_drugs %||% character()
    if (!isTRUE(input$order_consent)) {
      showNotification("Please confirm the demo-request consent before generating the bill.", type = "warning"); return()
    }
    if (!length(selected_ids)) {
      showNotification("No medicines carried over. Detect and confirm medicines on the Scan tab first.", type = "error"); return()
    }
    if (!nzchar(nm) || !grepl("^[0-9]{10}$", phone) || !nzchar(addr1) || !nzchar(city) || !nzchar(state) || !grepl("^[0-9]{6}$", pin)) {
      showNotification("Enter customer name, 10-digit mobile, house/street, city, state and 6-digit PIN code.", type = "error"); return()
    }
    b <- order_bill()
    pref <- input$order_preference %||% "generic"
    subtotal <- sum(b$chosen_line_total, na.rm = TRUE)
    gst <- round(subtotal * GST_RATE, 2)
    delivery <- if (subtotal > 0) DELIVERY_CHARGE else 0
    grand_total <- subtotal + gst + delivery
    generic_sub <- sum(b$generic_line_total, na.rm = TRUE)
    branded_sub <- sum(b$branded_line_total, na.rm = TRUE)
    generic_bill <- generic_sub + round(generic_sub * GST_RATE, 2) + if (generic_sub > 0) DELIVERY_CHARGE else 0
    branded_bill <- branded_sub + round(branded_sub * GST_RATE, 2) + if (branded_sub > 0) DELIVERY_CHARGE else 0
    s <- ranked(); s <- s[s$store_id == chosen_store(), , drop = FALSE]
    request_id <- paste0("DEMO-", format(Sys.time(), "%Y%m%d-%H%M%S"))
    item_lines <- paste0(b$brand_name, " / ", b$generic_name, " | packs: ", b$packs, " | status: ", ifelse(b$buyable, "available", "unavailable"), " | option: ", b$chosen_option, " | line total: ", ifelse(is.finite(b$chosen_line_total), sprintf("%.2f", b$chosen_line_total), "N/A"))
    order_request(list(
      request_id = request_id, created = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      patient_name = nm, phone = phone,
      address = paste(c(addr1, addr2[nzchar(addr2)], city, state, paste("PIN", pin)), collapse = ", "),
      pincode = pin, preference = pref, items = item_lines,
      store_name = if (nrow(s)) s$store_name[1] else "No store selected",
      stock_summary = paste0(sum(b$buyable, na.rm = TRUE), "/", nrow(b), " items available"),
      subtotal = subtotal, gst = gst, delivery = delivery, estimated_total = grand_total,
      generic_comparison_total = generic_bill, branded_comparison_total = branded_bill,
      rx_filename = if (!is.null(input$rx_img) && nrow(input$rx_img) > 0) input$rx_img$name[1] else "No image file; detected/typed prescription text used",
      notes = trimws(input$order_notes %||% ""),
      gst_rate = GST_RATE, delivery_charge = DELIVERY_CHARGE
    ))
    showNotification("Demo bill generated. No pharmacy has received an order.", type = "message", duration = 8)
  })

  output$order_request_summary <- renderUI({
    req_data <- order_request()
    if (is.null(req_data)) return(NULL)
    tagList(
      div(class = "alert alert-success",
        h4("Final estimated bill generated"),
        p(strong("Request ID: "), req_data$request_id),
        p(strong("Preference: "), switch(req_data$preference, generic = "Generic", branded = "Branded", either = "Either available / lower-priced option per item", req_data$preference)),
        p(strong("Selected store: "), req_data$store_name, " · ", req_data$stock_summary),
        p(strong("Subtotal: "), inr(req_data$subtotal), " · ", strong("GST: "), inr(req_data$gst), " · ", strong("Delivery: "), inr(req_data$delivery)),
        h4(paste("Grand total:", inr(req_data$estimated_total))),
        p(strong("Comparison including GST and delivery — Generic: "), inr(req_data$generic_comparison_total), " · ", strong("Branded: "), inr(req_data$branded_comparison_total)),
        p(strong("Delivery to: "), req_data$patient_name, " · ", req_data$phone, " · ", req_data$address),
        p(strong("Items:")), tags$ul(lapply(req_data$items, tags$li)),
        if (nzchar(req_data$notes)) p(strong("Delivery notes: "), req_data$notes),
        p(class = "disclaimer", "Demo estimate only. The prescription, stock, GST rate, delivery fee and final payable amount must be verified by a licensed pharmacy. No order, payment, stock reservation or delivery has been created.")),
      downloadButton("download_order_summary", "Download bill / request (CSV)", class = "btn btn-outline-primary"),
      if (!is.null(input$rx_img) && nrow(input$rx_img) > 0) downloadButton("download_order_bundle", "Download request + original Scan prescription (ZIP)", class = "btn btn-outline-primary")
    )
  })

  output$download_order_summary <- downloadHandler(
    filename = function() { d <- order_request(); paste0(if (is.null(d)) "demo-order" else d$request_id, "-bill.csv") },
    content = function(file) {
      d <- order_request(); req(d)
      out <- data.frame(
        request_id = d$request_id, created = d$created, patient_name = d$patient_name, phone = d$phone,
        delivery_address = d$address, pincode = d$pincode, medicine_preference = d$preference,
        selected_store = d$store_name, stock_summary = d$stock_summary,
        subtotal_inr = d$subtotal, gst_rate = d$gst_rate, gst_inr = d$gst,
        delivery_charge_inr = d$delivery, final_estimated_bill_inr = d$estimated_total,
        generic_comparison_incl_gst_delivery_inr = d$generic_comparison_total,
        branded_comparison_incl_gst_delivery_inr = d$branded_comparison_total,
        requested_medicines = paste(d$items, collapse = " || "), prescription_filename = d$rx_filename,
        notes = d$notes, status = "DEMO ONLY - NOT SENT TO PHARMACY", stringsAsFactors = FALSE)
      write.csv(out, file, row.names = FALSE, na = "")
    }
  )

  output$download_order_bundle <- downloadHandler(
    filename = function() { d <- order_request(); paste0(if (is.null(d)) "demo-order" else d$request_id, "-bundle.zip") },
    content = function(file) {
      d <- order_request(); req(d, !is.null(input$rx_img), nrow(input$rx_img) > 0)
      workdir <- tempfile("order_bundle_"); dir.create(workdir)
      on.exit(unlink(workdir, recursive = TRUE), add = TRUE)
      summary_path <- file.path(workdir, "order_bill.csv")
      write.csv(data.frame(request_id=d$request_id, customer=d$patient_name, phone=d$phone,
        address=d$address, preference=d$preference, selected_store=d$store_name,
        subtotal=d$subtotal, gst=d$gst, delivery=d$delivery, final_total=d$estimated_total,
        generic_comparison=d$generic_comparison_total, branded_comparison=d$branded_comparison_total,
        medicines=paste(d$items, collapse=" || "), status="DEMO ONLY - NOT SENT TO PHARMACY"), summary_path, row.names=FALSE)
      rx_path <- file.path(workdir, paste0("prescription_", gsub("[^A-Za-z0-9._-]", "_", basename(input$rx_img$name[1]))))
      if (!file.copy(input$rx_img$datapath[1], rx_path, overwrite=TRUE)) stop("Could not include the Scan-tab prescription file.")
      oldwd <- getwd(); setwd(workdir); on.exit(setwd(oldwd), add=TRUE)
      utils::zip(zipfile=file, files=c(basename(summary_path), basename(rx_path)), flags="-j")
    }
  )

  # ---- safety (locked until consult) ----
  output$safety_ui <- renderUI({
    if (!length(input$sel_drugs)) return(card(p("No medicines selected yet.")))
    if (input$consult == "none" || !isTRUE(input$consult_ack))
      return(card(class = "border-warning", p(strong("Locked."), "Please consult a pharmacist or doctor, then tick the box above.")))
    ids <- input$sel_drugs
    panels <- lapply(ids, function(id) {
      s <- safety[safety$drug_id == id, ]; f <- if (!is.null(fda)) fda[fda$drug_id == id, ] else NULL
      accordion_panel(drug_label(id), value = id, icon = icon("pills"),
        h6("Indication"), p(s$indication), h6("Contraindications"), p(s$contraindications),
        h6("Food / alcohol interactions"), p(s$food_interactions), h6("Key warnings"), p(s$key_warnings),
        if (!is.null(f) && nrow(f)) tagList(h6("FDA label excerpt (openFDA)"), p(class = "small", substr(f$contraindications[1], 1, 600))),
        p(class = "disclaimer", s$source))
    })
    pairs <- ddi[ddi$drug_a %in% ids & ddi$drug_b %in% ids, ]
    inter <- if (nrow(pairs)) tagList(lapply(seq_len(nrow(pairs)), function(i)
      div(class = paste("alert", ifelse(pairs$severity[i] == "Major", "alert-danger", "alert-warning")),
          strong(pairs$severity[i], ": "), drug_label(pairs$drug_a[i]), " + ", drug_label(pairs$drug_b[i]), " \u2013 ", pairs$note[i])))
      else div(class = "alert alert-success", "No interaction pairs flagged among the selected medicines (demo list is limited).")
    tagList(card(card_header("Combination check"), inter),
            card(card_header("Per-medicine safety"), do.call(accordion, c(panels, list(open = FALSE, multiple = TRUE)))))
  })
}
shinyApp(ui, server)