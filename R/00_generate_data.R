# Generates ALL synthetic datasets deterministically (same seed -> identical CSVs).
# Run from project root:  Rscript R/00_generate_data.R
source("R/config.R")
set.seed(SEED)
dir.create("data", showWarnings = FALSE)

## 1. Neurological drug master list (real generic/brand names; PRICES ARE SYNTHETIC, INR per pack) -------------
drugs <- data.frame(
  drug_id = sprintf("D%02d", 1:21),
  generic_name = c("levetiracetam","carbamazepine","phenytoin","valproate","lamotrigine","topiramate",
                   "gabapentin","pregabalin","levodopa carbidopa","pramipexole","ropinirole","donepezil",
                   "memantine","rivastigmine","sumatriptan","amitriptyline","clonazepam","baclofen",
                   "riluzole","oxcarbazepine","lacosamide"),
  brand_name = c("Keppra","Tegretol","Dilantin","Depakote","Lamictal","Topamax","Neurontin","Lyrica","Sinemet",
                 "Mirapex","Requip","Aricept","Namenda","Exelon","Imitrex","Elavil","Klonopin","Lioresal",
                 "Rilutek","Trileptal","Vimpat"),
  strength = c("500 mg","200 mg","100 mg","500 mg","100 mg","50 mg","300 mg","75 mg","100/25 mg","0.25 mg",
               "1 mg","5 mg","10 mg","3 mg","50 mg","25 mg","0.5 mg","10 mg","50 mg","300 mg","100 mg"),
  form = c(rep("tablet",6), rep("capsule",2), rep("tablet",5), "capsule", rep("tablet",7)),
  pack_size = c(rep(10,14), 4, rep(10,6)),
  therapeutic_class = c("Antiepileptic","Antiepileptic","Antiepileptic","Antiepileptic","Antiepileptic",
                        "Antiepileptic / migraine","Neuropathic pain / antiepileptic","Neuropathic pain / antiepileptic",
                        "Anti-parkinsonian","Anti-parkinsonian","Anti-parkinsonian","Anti-dementia","Anti-dementia",
                        "Anti-dementia","Anti-migraine (triptan)","Tricyclic (neuropathic pain / migraine prevention)",
                        "Benzodiazepine antiepileptic","Antispastic","ALS disease-modifying","Antiepileptic","Antiepileptic"),
  brand_mrp_inr = c(480,110,60,190,230,260,180,250,150,140,160,210,240,300,320,40,60,55,780,190,420),
  stringsAsFactors = FALSE
)
ratio <- round(runif(nrow(drugs), 0.20, 0.50), 2)         # generic is 20-50 % of brand MRP (synthetic)
drugs$generic_base_price_inr <- round(drugs$brand_mrp_inr * ratio * 2) / 2
write.csv(drugs, "data/drugs.csv", row.names = FALSE)

## 2. Stores in Jaipur (SYNTHETIC names; coordinates are approximate area centroids + jitter) --------------------
areas <- data.frame(
  area = c("Malviya Nagar","Vaishali Nagar","C-Scheme","Mansarovar","Jagatpura","Tonk Road","Sodala","Bani Park",
           "Raja Park","Civil Lines","Sanganer","Jhotwara","Vidhyadhar Nagar","Gopalpura"),
  lat  = c(26.8549,26.9115,26.9068,26.8498,26.8296,26.8700,26.9000,26.9350,26.8990,26.9150,26.8200,26.9400,26.9650,26.8650),
  lon  = c(75.8243,75.7435,75.8003,75.7650,75.8603,75.8000,75.7800,75.7900,75.8230,75.7760,75.7950,75.7400,75.7800,75.7700),
  stringsAsFactors = FALSE)
store_type <- sample(c("Jan Aushadhi Kendra","Private chemist","Hospital pharmacy"), nrow(areas), replace = TRUE, prob = c(.4,.4,.2))
stores <- data.frame(
  store_id   = sprintf("S%02d", seq_len(nrow(areas))),
  store_name = paste0("Demo ", store_type, " - ", areas$area),
  area       = areas$area,
  store_type = store_type,
  lat        = round(areas$lat + runif(nrow(areas), -0.004, 0.004), 5),
  lon        = round(areas$lon + runif(nrow(areas), -0.004, 0.004), 5),
  open_hours = ifelse(store_type == "Hospital pharmacy", "24x7", "09:00-21:00"),
  stringsAsFactors = FALSE)
write.csv(stores, "data/stores.csv", row.names = FALSE)

## 3. Generic inventory: store x drug (price + stock) ------------------------------------------------------------
grid <- expand.grid(store_id = stores$store_id, drug_id = drugs$drug_id, stringsAsFactors = FALSE)
grid <- grid[runif(nrow(grid)) < 0.75, ]                    # 75 % of store/drug pairs are listed
grid <- merge(grid, stores[, c("store_id","store_type")], by = "store_id")
grid <- merge(grid, drugs[, c("drug_id","generic_base_price_inr")], by = "drug_id")
mult <- ifelse(grid$store_type == "Jan Aushadhi Kendra", 0.85, ifelse(grid$store_type == "Hospital pharmacy", 1.05, 1))
grid$generic_price_inr <- round(grid$generic_base_price_inr * mult * runif(nrow(grid), 0.92, 1.08), 1)
grid$stock_packs <- pmax(0L, rpois(nrow(grid), 18) - 3L)
grid$stock_packs[runif(nrow(grid)) < 0.10] <- 0L            # 10 % listed-but-out-of-stock
grid$last_updated <- "2026-10-01"                           # fixed string: no Sys.Date() -> reproducible
grid <- grid[order(grid$store_id, grid$drug_id), ]
inventory <- grid[, c("store_id","drug_id","generic_price_inr","stock_packs","last_updated")]
write.csv(inventory, "data/inventory.csv", row.names = FALSE)

## 4. Safety data (DEMO paraphrase for prototype; replace with openFDA / DrugBank extract - see README) ----------
safety <- data.frame(
  drug_id = drugs$drug_id,
  indication = c(
    "Partial-onset, myoclonic and primary generalised tonic-clonic seizures.",
    "Epilepsy (partial and generalised tonic-clonic seizures); trigeminal neuralgia.",
    "Generalised tonic-clonic and focal seizures; seizure prevention around neurosurgery.",
    "Epilepsy; manic episodes of bipolar disorder; migraine prevention.",
    "Epilepsy (adjunct or monotherapy); maintenance treatment of bipolar I disorder.",
    "Epilepsy; migraine prevention.",
    "Postherpetic neuralgia; partial-onset seizures.",
    "Neuropathic pain (diabetic, postherpetic); fibromyalgia; adjunct for partial seizures.",
    "Parkinson's disease and parkinsonism.",
    "Parkinson's disease; restless legs syndrome.",
    "Parkinson's disease; restless legs syndrome.",
    "Dementia of the Alzheimer's type (mild to severe).",
    "Moderate to severe dementia of the Alzheimer's type.",
    "Mild to moderate Alzheimer's dementia; dementia associated with Parkinson's disease.",
    "Acute treatment of migraine with or without aura.",
    "Depression; low-dose use for neuropathic pain or migraine prevention is common (often off-label).",
    "Seizure disorders; panic disorder.",
    "Spasticity from multiple sclerosis or spinal cord disease.",
    "Amyotrophic lateral sclerosis (ALS).",
    "Partial-onset seizures.",
    "Partial-onset seizures; adjunct in primary generalised tonic-clonic seizures."),
  contraindications = c(
    "Hypersensitivity to levetiracetam or any component.",
    "Hypersensitivity (incl. tricyclic compounds); history of bone marrow depression; MAO inhibitors within 14 days.",
    "Hypersensitivity to hydantoins.",
    "Significant liver disease; mitochondrial (POLG) disorders; urea cycle disorders; pregnancy when used for migraine prevention; hypersensitivity.",
    "Hypersensitivity to lamotrigine or any component.",
    "No absolute contraindication for epilepsy use on the label; caution in metabolic acidosis, kidney stones, angle-closure glaucoma.",
    "Hypersensitivity to gabapentin or any component.",
    "Hypersensitivity to pregabalin or any component.",
    "Narrow-angle glaucoma; non-selective MAO inhibitors; suspicious undiagnosed skin lesions or history of melanoma.",
    "Hypersensitivity to pramipexole or any component.",
    "Hypersensitivity to ropinirole or any component.",
    "Hypersensitivity to donepezil or piperidine derivatives.",
    "Hypersensitivity to memantine or any component.",
    "Hypersensitivity to rivastigmine or other carbamate derivatives (e.g., prior skin reaction to the patch).",
    "Ischaemic heart disease; uncontrolled hypertension; hemiplegic or basilar migraine; MAO-A inhibitor within 2 weeks; other triptan or ergot within 24 h; severe hepatic impairment.",
    "MAO inhibitors within 14 days; recent myocardial infarction; hypersensitivity.",
    "Significant liver disease; acute narrow-angle glaucoma; hypersensitivity to benzodiazepines; severe respiratory insufficiency.",
    "Hypersensitivity to baclofen or any component.",
    "Hypersensitivity to riluzole or any component.",
    "Hypersensitivity to oxcarbazepine or eslicarbazepine.",
    "No contraindication on the US label; caution with cardiac conduction disorders."),
  food_interactions = c(
    "No major food interaction. Alcohol may increase drowsiness.",
    "Grapefruit juice may raise drug levels. Avoid alcohol.",
    "Enteral/tube feeds can reduce absorption (separate by about 2 h). Alcohol alters levels.",
    "Take with food to reduce stomach upset. Avoid alcohol.",
    "No significant food interaction. Alcohol may increase dizziness.",
    "Stay well hydrated (kidney stone risk). Avoid alcohol. Ketogenic diets may raise acidosis risk.",
    "Aluminium/magnesium antacids reduce absorption (separate by about 2 h). Avoid alcohol.",
    "Can be taken with or without food. Alcohol adds to drowsiness and dizziness.",
    "High-protein meals can reduce effect; iron supplements reduce absorption. Often taken 30 min before meals.",
    "Can be taken with or without food. Alcohol increases sleepiness.",
    "Taking with food reduces nausea. Alcohol increases sleepiness.",
    "No major food interaction. Take in the evening if vivid dreams or insomnia occur.",
    "High doses of urine-alkalinising agents (e.g., sodium bicarbonate) can raise drug levels.",
    "Take with meals to reduce nausea and vomiting.",
    "No major food interaction. Avoid frequent use (medication-overuse headache).",
    "Alcohol increases sedation. Grapefruit juice may raise levels. St John's wort adds serotonin risk.",
    "Alcohol: dangerous additive sedation and breathing depression. Grapefruit juice may raise levels.",
    "Alcohol adds sedation. Do not stop suddenly.",
    "High-fat meals reduce absorption; take on an empty stomach. Charbroiled food and heavy caffeine intake may alter metabolism.",
    "Can be taken with or without food. Avoid alcohol.",
    "No major food interaction. Avoid alcohol."),
  key_warnings = c(
    "Mood or behaviour changes; adjust dose in kidney impairment.",
    "Serious skin reactions (genetic risk screening advised in some populations); low sodium; blood count monitoring.",
    "Narrow therapeutic window; gum overgrowth; serious skin reactions.",
    "Liver injury; pancreatitis; major birth-defect risk.",
    "Serious rash - titrate slowly; valproate roughly doubles lamotrigine levels.",
    "Acute myopia/glaucoma; cognitive slowing; birth-defect risk.",
    "Dizziness; breathing depression with opioids or sedatives.",
    "Swelling, weight gain; misuse potential; dose-adjust in kidney impairment.",
    "Dyskinesia; sudden sleep onset; low blood pressure on standing.",
    "Sleep attacks; impulse-control problems; hallucinations.",
    "Sleep attacks; some antibiotics (e.g., ciprofloxacin) raise levels.",
    "Slow heart rate and fainting; stomach bleeding risk.",
    "Dizziness; dose-adjust in severe kidney impairment.",
    "Weight loss; slow heart rate.",
    "Serotonin syndrome with SSRIs/SNRIs; chest tightness.",
    "Heart rhythm effects; anticholinergic effects; mood worsening in young people.",
    "Dependence and withdrawal; do not combine with opioids.",
    "Abrupt withdrawal can cause seizures or hallucinations.",
    "Liver enzyme monitoring; low white-cell count.",
    "Low sodium; may reduce effect of hormonal contraceptives.",
    "ECG PR-interval prolongation; dizziness."),
  source = "DEMO summary written for prototype; verify against current FDA label / DrugBank before any clinical use",
  stringsAsFactors = FALSE)
stopifnot(nrow(safety) == nrow(drugs))
write.csv(safety, "data/safety.csv", row.names = FALSE)

## 5. Drug-drug interaction / duplication pairs among the catalogue (DEMO) ---------------------------------------
pair <- function(a, b, sev, note) data.frame(drug_a = a, drug_b = b, severity = sev, note = note, stringsAsFactors = FALSE)
interactions <- rbind(
  pair("D05","D04","Major","Valproate roughly doubles lamotrigine levels; higher rash risk - dose reduction needed."),
  pair("D06","D04","Moderate","Combination can cause raised ammonia / encephalopathy."),
  pair("D02","D05","Moderate","Carbamazepine lowers lamotrigine levels."),
  pair("D03","D04","Moderate","Phenytoin and valproate alter each other's blood levels."),
  pair("D02","D20","Moderate","Two sodium-channel antiepileptics; additive low-sodium and dizziness risk."),
  pair("D17","D07","Moderate","Additive sedation / breathing depression."),
  pair("D17","D08","Moderate","Additive sedation / breathing depression."),
  pair("D17","D18","Moderate","Additive sedation."),
  pair("D15","D16","Major","Serotonin syndrome risk; needs prescriber review."),
  pair("D10","D11","Major","Duplicate therapy: two dopamine agonists."),
  pair("D12","D14","Major","Duplicate therapy: two cholinesterase inhibitors."),
  pair("D07","D08","Moderate","Duplicate therapy: two gabapentinoids; additive dizziness and sedation."))
write.csv(interactions, "data/interactions.csv", row.names = FALSE)

## 6. Manifest (checksums prove two runs produced identical data) ------------------------------------------------
f <- list.files("data", pattern = "\\.csv$", full.names = TRUE)
f <- f[!grepl("openfda", f)]
writeLines(paste(unname(tools::md5sum(f)), basename(f)), "data/MANIFEST.md5")
message("Data written: ", paste(basename(f), collapse = ", "))
