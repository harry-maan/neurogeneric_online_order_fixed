# neurogeneric_online_order_fixed
NEUROGENERIC FINDER — PACKAGE 

Version: Prototype / synthetic demo Purpose: NeuroGeneric Finder
demonstrates a neurology-focused prescription matching and medicine-cost
comparison workflow. It is a research/demo application, not a production
pharmacy service.

1. WHAT THIS PACKAGE CONTAINS

This ZIP is a patch package for an existing NeuroGeneric Finder Shiny
project. It contains: - app.R — Shiny interface and server logic,
including Scan, Stores & savings, Safety, and Online order tabs. -
www/app.js — browser-side helper functions, including voice/GPS
interface support. - www/style.css — responsive styling and navigation
adjustments. - README.txt — these installation and usage notes.

IMPORTANT: This is not a fully standalone project ZIP. The app.R
included here expects the existing project folders and files described
below. Keep your current R/ and data/ folders when installing this
patch.

2. REQUIRED PROJECT STRUCTURE

Your project directory should contain at least:

app.R R/ config.R helpers.R 00_generate_data.R data/ drugs.csv
stores.csv inventory.csv safety.csv interactions.csv [optional]
openfda_labels.csv www/ app.js style.css

If data/drugs.csv does not exist, app.R attempts to source
R/00_generate_data.R to create the demo data. The required R helper and
data-generation files are not included in this patch ZIP; retain them
from your existing project.

3. REQUIRED SOFTWARE AND R PACKAGES

Software: - R (use a currently supported R 4.x release; R 4.2 or newer
is recommended). - RStudio is optional but convenient. - A current web
browser. On mobile, the browser and local network must be able to reach
the computer running Shiny.

Required R packages: - shiny — application framework. - bslib —
Bootstrap-based layout, cards and navigation. - DT — interactive data
tables.

Install required packages in the R console:

install.packages(c(“shiny”, “bslib”, “DT”))

Packages used by the app or its optional features: - htmltools — HTML
escaping and tags; normally installed as a dependency of Shiny. -
leaflet — optional interactive store map. Without it, the app displays a
message instead of the map. - magick and tesseract — optional
image-processing/OCR packages for reading prescription images. Without
both, users can type or speak medicine names instead. - utils — included
with base R; used for CSV output and ZIP creation.

Optional integrations: - Browser speech recognition and geolocation
depend on browser support and user permission. - The optional LLM
text-reading checkbox requires the matching API key/environment setup
and network access. Do not enable it with real patient information
unless the integration has been reviewed for privacy, consent, security
and applicable law. - Internet access may be required to install
packages and to load external map tiles. The core demo can use synthetic
store coordinates and inventory.

Optional package installation:

install.packages(c(“leaflet”, “magick”, “tesseract”))

Note: OCR package installation may require system libraries or
additional setup on macOS/Linux/Windows. Follow the package installation
instructions for your operating system.

4. SYNTHETIC DATASET — NEUROGENERIC ONLY

The intended demo catalogue is limited to medicines used in the
NeuroGeneric/neurology demonstration workflow. The sample prescription
text in this project uses: - Keppra (levetiracetam) 500 mg - Lamictal
(lamotrigine) 100 mg - Sinemet (carbidopa/levodopa) 100/25

These names are examples for demonstrating text matching and are not a
recommendation, prescription, or confirmation that a medicine is
appropriate for any patient.

The project’s demo data files should be synthetic: - drugs.csv — demo
medicine catalogue, names, strengths and matching IDs. - stores.csv —
invented store names, areas and coordinates. - inventory.csv — invented
stock quantities and illustrative prices. - safety.csv — demo safety
text for interface testing. - interactions.csv — demo interaction rows
for interface testing. - openfda_labels.csv — optional label excerpts if
separately configured.

No real pharmacy inventory, customer records, patient records,
prescription history, verified medicine prices, or live availability is
supplied by this patch. If you use a generated demo dataset, keep it
restricted to the intended NeuroGeneric demonstration catalogue and
clearly label it SYNTHETIC / NOT FOR CLINICAL USE. Do not treat
generated safety or interaction examples as clinical evidence.

5. INSTALLATION

1.  Stop the running Shiny app.

2.  Back up the current app.R and www folder.

3.  Extract this ZIP.

4.  Replace the project’s app.R with the included app.R.

5.  Copy www/app.js and www/style.css into the project’s existing www/
    folder. Back up any files before overwriting.

6.  Keep the existing R/ and data/ folders. Do not delete them.

7.  In RStudio, set the working directory to the project root (the
    folder containing app.R), or use setwd(“path/to/your/project”).

8.  Install required packages if needed.

9.  Start the app from the project root:

    shiny::runApp(host = “0.0.0.0”, port = 3838)

The app.R file should not call shiny::runApp() from inside itself. Start
the application from the R console as shown above. Port 3838 is the
example port used by this package; choose another free port if needed.

To open the app on the same computer, use the local URL printed by
Shiny, commonly http://127.0.0.1:3838. To access it from a phone on the
same Wi-Fi, use the computer’s local LAN IP address with port 3838, for
example http://192.168.1.20:3838. Replace the example IP with the
computer’s actual local IP. Do not expose the demo app directly to the
public internet.

6. BASIC WORKFLOW

1.  Scan tab: upload a prescription image, load the demo prescription,
    speak, or type medicine text.

2.  Select Detect medicines, then review the matches and quantities.
    Untick any incorrect match.

3.  Choose your location or use GPS if the browser permits it.

4.  Select Find nearest stores to see the synthetic store and stock
    comparison.

5.  In Stores & savings, review availability and select a store. Click
    Proceed to home-delivery order.

6.  Online order: choose Generic, Branded, or Either available; complete
    the delivery address; review the estimated bill and
    generic-versus-branded comparison; then generate a demo
    bill/request.

7.  Download the CSV request summary if required. A prescription bundle
    may be offered when an image was uploaded.

8.  EXAMPLE PROBLEM AND SOLUTION

    Problem: A user scans a neurology prescription containing “Keppra
    500 mg” and “Lamictal 100 mg”. The medicine matches are detected in
    the Scan tab, but the Online order tab is not visible in the
    navigation, so the user cannot continue to the delivery-address and
    bill-generation steps.

Solution provided by this tool: - Update app.R so the navbar explicitly
contains an Online order nav_panel with value “order”. - Keep the tab
navigation usable on narrow screens and add a shortcut from the Scan
tab. - Ensure the correct updated app.R is the one being launched. -
Keep the existing R/ and data/ folders and copy the matching www/app.js
and www/style.css files. - Restart the app from the project root with
shiny::runApp(host = “0.0.0.0”, port = 3838). - After confirming
medicines and selecting a store, use Proceed to home-delivery order. The
order tab should reuse the medicines selected in Scan; it should not ask
for a second scan.

If the tab remains missing, verify that the R console is running the
intended project directory and that no older app.R is being launched.
Check the console for errors and confirm that www assets were copied to
the same project.

8. DEMO BILL AND LIMITATIONS

The current prototype uses illustrative demo assumptions of 5% GST and
₹40 delivery charge in its bill display. These values are not tax or
delivery advice and must be verified and replaced with applicable rates
and actual pharmacy fees before any real transaction.

The prototype does not transmit orders to a pharmacy, confirm live
stock, reserve medicines, process payment, verify prescriptions with a
pharmacist, or arrange delivery. A generated bill is an estimate only.
Any real deployment needs a verified pharmacy partner, secure order
backend, live inventory/pricing, pharmacist review, consent and privacy
controls, secure prescription handling, retention/deletion policy,
payment/delivery integration, and legal/regulatory review.

9. SAFETY, PRIVACY AND RESPONSIBLE USE

-   Use synthetic patient and prescription details for testing.
-   Do not enter real patient information into a demo deployment.
-   Do not use demo matching, safety or interaction output to make
    treatment decisions.
-   Medicine substitutions must be reviewed by a licensed pharmacist or
    prescriber.
-   Do not claim that a medicine is in stock or safe based only on
    synthetic data.
-   Protect API keys; never hard-code secrets in source code or share
    them in screenshots.
-   Keep the app on a trusted local network while testing.

10. TROUBLESHOOTING

Online order tab missing: - Confirm the updated app.R was copied into
the project actually being run. - Confirm the nav_panel(“Online order”,
value = “order”, …) block is present. - Restart Shiny after saving. -
Run shiny::runApp() from the project root. - Check the R console for a
syntax error that may stop UI creation.

Missing helper/data file: - Restore R/config.R, R/helpers.R and
R/00_generate_data.R from the existing project. - Confirm the data files
listed in Section 2 exist or that the data generator is available.

OCR does not work: - Install and configure both magick and tesseract.
Otherwise type or speak the medicine names.

Store map does not appear: - Install leaflet. The rest of the demo
should still be usable without the map.

ZIP download fails: - Confirm a system ZIP utility is available and that
the app has permission to write temporary files.
11. TEAM
-------
[Tech_Solver]
[Harmandeep-Research Scientist: 8 year of research experience in AIIMS hospital, 
Harvinder  Singh, Scientist: ICMR-NIHR, Jodhpur, Developer]
[9587677525 harvinders.hq@icmr.gov.in]

12. LICENSE
----------
[Add a license, "All rights reserved"]


END OF README
