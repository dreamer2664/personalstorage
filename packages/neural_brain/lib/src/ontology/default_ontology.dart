/// The built-in bilingual (EN/IT) concept ontology, in a compact line-based DSL:
///
///     id[@prior] > parent1,parent2 | English label | Etichetta italiana | en terms ; it terms
///
/// * `>` lists parents (`-` for a top-level *domain*, which becomes a user-visible category).
/// * `@prior` (domains only) is a tie-break weight used when choosing a note's category.
/// * Terms are whitespace separated; `_` joins the words of a phrase (`toilet_paper`).
/// * Term markers (prefix, any order): `~` weak/ambiguous (`~call`), `!` strong (`!startup_idea`),
///   `^` only at the start of a line or sentence (`^idea` matches "Idea: ..." but not "gift ideas").
/// * Single-word labels are implicitly search terms; multi-word labels are not (list them).
/// * Terms are stemmed at load time, so `egg` also matches `eggs` and `uova` matches `uovo`.
///
/// Extending the brain is a matter of adding lines here (or passing your own DSL to
/// `Ontology.parse`). Bump [defaultOntologyVersion] so that stored notes are re-indexed.
library;

const int defaultOntologyVersion = 5;

const String defaultOntologyDsl = r'''
# ───────────────────────── Shopping & errands ─────────────────────────
shopping > - | Shopping | Acquisti | shop shopping purchase ~buy ~order ~store mall errand errands checkout cart discount coupon refund receipt delivery parcel ~package amazon ebay etsy zalando ~return ; acquisti acquistare ~comprare negozio commissioni sconto saldi rimborso scontrino consegna pacco
groceries > shopping,food | Groceries | Spesa | grocery supermarket milk egg bread butter cheese yogurt cream flour sugar salt pepper pasta rice cereal oats coffee tea juice water_bottles soda fruit apple banana orange lemon strawberry grape vegetable veggies tomato potato onion garlic carrot salad lettuce cucumber spinach zucchini broccoli chicken beef pork fish salmon tuna meat sausage ham bacon olive_oil vinegar honey jam nuts pantry fridge freezer snacks cookies chocolate basil parmesan mozzarella herbs spices oregano ; spesa supermercato latte uova pane burro formaggio yogurt panna farina zucchero sale pepe pasta riso cereali caffè tè succo acqua frutta mela banana arancia limone fragola uva verdura pomodoro patate cipolla aglio carote insalata zucchine broccoli pollo manzo maiale pesce salmone tonno carne salsiccia prosciutto olio aceto miele marmellata noci dispensa frigo congelatore biscotti cioccolato basilico parmigiano mozzarella erbe spezie origano
household_supplies > shopping,home | Household supplies | Articoli per la casa | detergent soap shampoo toothpaste toilet_paper paper_towels trash_bags batteries light_bulb sponge laundry_detergent cleaning_supplies dish_soap conditioner deodorant razor tissues supplies ; detersivo sapone shampoo dentifricio carta_igienica scottex sacchetti pile lampadina spugna ammorbidente deodorante rasoio fazzoletti
clothing > shopping | Clothing | Abbigliamento | clothes shirt tshirt jeans trousers shoes sneakers boots jacket coat dress skirt socks underwear hat scarf sweater hoodie suit tailor ; vestiti abbigliamento camicia maglietta pantaloni scarpe stivali giacca cappotto abito gonna calzini intimo cappello sciarpa maglione felpa sarto
gifts > shopping,people | Gifts | Regali | gift gifts present birthday_gift wrap flowers bouquet souvenir ; regalo regali fiori mazzo souvenir pensiero

# ───────────────────────── Food & cooking ─────────────────────────
food > - | Food & Cooking | Cibo e cucina | food eat meal cook cooking ingredient dinner lunch breakfast snack dish cuisine hungry taste ; cibo mangiare pasto cucinare ingrediente cena pranzo colazione spuntino piatto cucina
recipes > food | Recipes | Ricette | recipe bake baking roast grill simmer marinate dough oven sauce stew soup salad dessert cake cookie pancake risotto carbonara tiramisu casserole sourdough whisk knead preheat tablespoon teaspoon ; ricetta ricette infornare forno impasto sugo zuppa torta dolce lievito mescolare cottura cucchiaio tiramisù lasagne
restaurants > food,travel | Restaurants & cafés | Ristoranti e locali | aperitivo happy_hour restaurant cafe bar pizzeria trattoria osteria reservation table_for menu brunch takeaway takeout sushi bistro michelin tasting ramen noodles burger steak taco tacos curry kebab dumplings pho paella gelato icecream bakery croissant diner eatery ; ristorante locale pizzeria trattoria osteria prenotazione tavolo menù aperitivo asporto
drinks > food | Drinks | Bevande | coffee espresso cappuccino latte_macchiato tea wine beer cocktail whisky gin vodka juice smoothie spritz ~drink ; caffè espresso cappuccino tè vino birra cocktail whisky succo frullato spritz ~bere

# ───────────────────────── Health & wellness ─────────────────────────
health > - | Health & Wellness | Salute e benessere | health healthy medical medicine symptom therapy prescription hospital clinic checkup vaccine allergy pain sick ill fever cold flu wellness ; salute sano medico medicina sintomo terapia ricetta_medica ospedale visita controllo vaccino allergia dolore malato febbre raffreddore influenza benessere
medical > health | Medical | Visite mediche | doctor dentist dentist_appointment !physical_therapy physiotherapist knee back_pain shoulder injury sprain physician nurse surgery blood_test lab_results xray mri specialist pharmacy pills antibiotics physiotherapy optician eye_exam dermatologist cardiologist gp blood checkup ; medico dottore dentista infermiere chirurgia analisi prelievo esami radiografia risonanza specialista farmacia pillole antibiotico fisioterapia oculista dermatologo cardiologo
fitness > health | Fitness | Fitness | gym workout exercise running jog jogging yoga pilates swim swimming cycling bike hike hiking stretch weights pushups squat marathon half_marathon cardio training steps 5k 10k crossfit ~run ; palestra allenamento esercizio corsa correre nuoto nuotare bicicletta bici yoga pilates camminata escursione pesi flessioni maratona cardio passi
nutrition > health,food | Nutrition | Alimentazione | diet calories protein vitamins supplements ~fasting hydration macros weight_loss meal_prep vegan vegetarian gluten intolerance ; dieta calorie proteine vitamine integratori digiuno idratazione dimagrire vegano vegetariano glutine intolleranza
mental_health > health | Mind & sleep | Mente e sonno | meditation meditate meditating mindfulness therapy anxiety anxious stressed worried overwhelmed sad tired exhausted headache insomnia sleep insomnia mood gratitude burnout relax rest therapist breathing ; meditazione meditare mindfulness ansia ansioso stressato stanco sonno insonnia umore gratitudine burnout rilassarsi riposo psicologo respirazione

# ───────────────────────── Money & bills ─────────────────────────
finance > - | Money & Bills | Soldi e bollette | money finance financial payment invoice bill bills cost price budget expense expenses income salary cash card bank account transfer tax taxes cheap expensive euro dollars ~pay ; soldi finanza finanziario pagamento fattura bolletta bollette costo prezzo budget spese stipendio contanti carta banca conto bonifico tasse economico costoso euro dollari ~pagare
bills > finance,admin | Bills & subscriptions | Bollette e abbonamenti | bill bills electricity gas_bill water_bill internet_bill phone_bill rent mortgage utilities subscription netflix_subscription insurance_premium due_date late_fee direct_debit ; bolletta bollette luce affitto mutuo utenze abbonamento canone scadenza addebito condominio
banking > finance | Banking | Banca | bank iban transfer deposit withdraw credit_card debit_card loan overdraft atm wire swift revolut paypal ; banca iban bonifico deposito prelievo carta_di_credito prestito bancomat scoperto paypal
taxes > finance,admin | Taxes | Tasse | tax taxes irs vat tax_return accountant deduction filing ; tasse imposte iva dichiarazione commercialista detrazione 730 f24 modello_unico isee
investing > finance | Investing | Investimenti | invest investment stock stocks etf etfs crypto bitcoin ethereum portfolio dividend fund savings retirement pension shares market trading bonds ; investimento investire azioni etf criptovalute portafoglio dividendo fondo risparmio pensione borsa obbligazioni

# ───────────────────────── Work & career ─────────────────────────
work > - | Work & Career | Lavoro e carriera | work job office career boss manager colleague coworker ~team company ~business deadline ~report ~presentation workplace slides slide_deck powerpoint keynote quarterly q1 q2 q3 q4 okr ; lavoro ufficio carriera capo responsabile collega squadra azienda scadenza relazione ~presentazione slide trimestrale
meetings > work,people | Meetings | Riunioni | meeting standup sync agenda meeting_minutes one_on_one retro workshop conference_call zoom teams_call calendar_invite offsite kickoff ; riunione incontro agenda verbale videochiamata invito_calendario workshop
projects > work | Projects | Progetti | project milestone roadmap sprint backlog deliverable launch release scope stakeholder planning timeline ~plan ; progetto traguardo roadmap sprint consegna lancio rilascio pianificazione cronoprogramma ~piano
email_comms > work | Email & messages | Email e messaggi | email mail inbox follow_up newsletter memo slack messages ~message ~reply ~send ; email posta casella newsletter promemoria messaggi ~rispondere ~inviare
careers > work | Career | Carriera | resume cv interview hiring salary raise promotion linkedin ~networking job_offer contract job_search recruiter ; curriculum colloquio assunzione stipendio aumento promozione linkedin offerta_di_lavoro contratto selezionatore
sales_clients > work | Clients & sales | Clienti e vendite | client clients customer proposal quote pitch lead prospect sales deal negotiation pricing crm ; cliente clienti preventivo proposta vendite trattativa negoziazione listino

# ───────────────────────── Tech & code ─────────────────────────
tech > - | Tech & Code | Tecnologia e codice | tech technology software computer digital online website internet wifi update updates ; tecnologia software computer digitale sito rete aggiornamenti aggiornamento app
programming > tech | Programming | Programmazione | code coding bug debug refactor commit git github gitlab stackoverflow repo repository api function class database databases sql backend frontend deploy server unit_test typescript python dart flutter react javascript java swift kotlin compile build pipeline docker kubernetes library framework pull_request merge app_bug login typo typos landing_page webpage web_page css html button responsive ~fix ; codice programmare programmazione errore repository funzione database distribuzione server libreria
ai_ml > tech | AI & machine learning | AI e machine learning | ai ml machine_learning neural network neural_network transformer transformers llm gpt embedding embeddings vector vectors training dataset inference prompt chatbot nlp deep_learning semantic ; intelligenza_artificiale rete_neurale modello addestramento apprendimento_automatico embedding vettore semantico
gadgets > tech,shopping | Gadgets | Dispositivi | phone iphone android laptop macbook tablet ipad headphones airpods charger cable monitor keyboard mouse camera smartwatch gadget device printer router hdmi ; laptop telefono cellulare portatile cuffie caricatore cavo schermo tastiera fotocamera orologio dispositivo stampante
security > tech | Security & privacy | Sicurezza e privacy | password passcode 2fa vpn security privacy backup encrypt phishing ~login ; password sicurezza privacy crittografia accesso backup

# ───────────────────────── Learning & reading ─────────────────────────
learning@0.85 > - | Learning & Reading | Studio e lettura | learn study reading lesson class exam homework school university lecture tutorial knowledge wikipedia khan ~read ; imparare studiare lettura lezione esame compiti scuola università lezione tutorial conoscenza wikipedia ~leggere
books > learning | Books | Libri | ~book novel author chapter ~page kindle audiobook library read_later bestseller fiction nonfiction biography paperback ; libro libri romanzo autore capitolo pagina biblioteca audiolibro biografia
courses > learning | Courses & study | Corsi e studio | course syllabus mooc udemy coursera certificate degree module assignment quiz exam study_plan flashcards thesis semester ; corso programma_di_studio certificato laurea modulo compito quiz piano_di_studio tesi semestre
research > learning,work | Research | Ricerca | research paper journal hypothesis experiment data analysis findings citation literature_review survey benchmark evaluate compare investigate arxiv scholar pubmed doi preprint ; ricerca articolo_scientifico ipotesi esperimento analisi dati bibliografia sondaggio confrontare indagare arxiv
languages > learning | Languages | Lingue | language vocabulary grammar spanish french italian german english japanese translate translation pronunciation duolingo fluency verbs ; lingua vocabolario grammatica spagnolo francese italiano tedesco inglese giapponese tradurre traduzione pronuncia verbi

# ───────────────────────── Travel & places ─────────────────────────
travel > - | Travel & Places | Viaggi e luoghi | travel trip vacation holiday journey abroad tour destination getaway tripadvisor skyscanner ; viaggio viaggiare vacanza ferie vacanze destinazione gita
transport > travel | Flights & transport | Voli e trasporti | flight flights airline airport boarding_pass layover train_ticket train_tickets station bus taxi uber rental_car ferry metro passport visa luggage baggage transport transportation commute ; volo voli compagnia_aerea aeroporto carta_imbarco scalo treno biglietto stazione autobus taxi noleggio_auto traghetto metropolitana passaporto visto bagaglio valigia trasporti
lodging > travel | Stays | Alloggi | hotel hostel airbnb booking reservation check_in check_out room suite resort camping bnb stay accommodation lodging ; albergo hotel ostello prenotazione camera appartamento campeggio alloggio
itinerary > travel | Itinerary | Itinerario | itinerary sightseeing museum landmark beach attraction map guide excursion day_trip trail viewpoint ; itinerario visita museo spiaggia attrazione mappa guida escursione gita sentiero
places > travel | Places | Luoghi | ~place ~places city country neighborhood paris london rome milan lisbon berlin tokyo new_york barcelona madrid amsterdam venice florence naples colosseum eiffel vatican duomo ; città paese quartiere parigi londra roma milano lisbona berlino tokyo new_york barcellona madrid amsterdam venezia firenze napoli colosseo vaticano duomo

# ───────────────────────── Home & living ─────────────────────────
home > - | Home & Living | Casa | home house apartment flat room kitchen bathroom bedroom furniture desk desks chair chairs sofa couch mattress shelf landlord neighbor moving ; casa appartamento stanza cucina bagno camera mobili padrone_di_casa vicino trasloco
chores > home | Chores | Faccende domestiche | clean cleaning vacuum laundry dishes trash garbage tidy organize declutter donate garage attic basement closet wardrobe mop dust iron sweep dishwasher ; pulire pulizie aspirapolvere bucato piatti spazzatura riordinare stirare lavastoviglie scopa
repairs > home | Repairs & DIY | Riparazioni e fai da te | repair broken leak leaking clogged drain shower toilet sink plumber electrician paint renovation drill screw tools maintenance handyman boiler heating air_conditioner diy tap faucet ~fix ; riparare rotto perdita idraulico elettricista dipingere ristrutturazione trapano viti attrezzi manutenzione caldaia riscaldamento climatizzatore fai_da_te rubinetto
garden > home | Garden & plants | Giardino e piante | garden plant plants water_the flowers seeds lawn mow herbs pot soil compost balcony succulent succulents ; giardino pianta piante annaffiare fiori semi prato erba vaso terriccio compost balcone
pets > home,people | Pets | Animali domestici | pet dog cat vet leash litter puppy kitten aquarium hamster walk_the_dog ; animale cane gatto veterinario guinzaglio lettiera cucciolo gattino acquario criceto passeggiata_cane

# ───────────────────────── People & social ─────────────────────────
people > - | People & Social | Persone e social | !family !friend !friends !mom !dad !mother !father !sister !brother !wife !husband !girlfriend !boyfriend !parents !grandma !grandpa cousin uncle aunt neighbour social people ; !famiglia !amico !amici !mamma !papà !madre !padre !sorella !fratello !moglie !marito !genitori !nonna !nonno cugino zio zia vicino sociale persone compagno compagna fidanzata fidanzato
calls_messages > people | Calls & messages | Chiamate e messaggi | phone text whatsapp callback voicemail ring ~call ~calls ~message ; telefonare whatsapp richiamare segreteria squillo ~chiamare ~messaggio
events > people | Events | Eventi | birthday anniversary wedding party dinner_party invite reunion gathering celebration baby_shower graduation rsvp ; compleanno anniversario matrimonio festa invito rimpatriata celebrazione laurea
kids_family > people | Kids & family | Bambini e famiglia | kids children school_pickup pediatrician daycare babysitter playdate parent_teacher nursery toddler baby ; bambini figli figlio figlia scuola pediatra asilo babysitter neonato

# ───────────────────────── Ideas & creativity ─────────────────────────
ideas@0.85 > - | Ideas & Creativity | Idee e creatività | ^idea ~idea ~thought !brainstorm invention innovation inspiration !what_if creative vision ~concept ; ^idea ~idea ~pensiero !brainstorming invenzione innovazione ispirazione creativo visione ~concetto
business_ideas > ideas,work | Startup & product ideas | Idee di business | !startup !startup_idea !business_idea !app_idea !product_idea !side_project saas mvp monetize revenue ~market ~product ~feature pitch ~strategy ~growth ~users marketplace ; !startup !idea_di_business !idea_per_una_app !progetto_parallelo saas mvp monetizzare ricavi ~mercato ~prodotto ~funzionalità strategia crescita ~utenti marketplace
writing > ideas | Writing | Scrittura | write writing blog blog_post essay draft story novel article headline script poem outline chapter_draft ; scrivere scrittura blog articolo bozza storia romanzo poesia sceneggiatura scaletta
design > ideas | Design | Design | design ui ux logo color palette typography layout wireframe prototype figma sketch branding mockup illustration icon ; design grafica logo colore palette tipografia prototipo illustrazione icona
music_art > ideas,media | Music & art | Musica e arte | music song guitar piano lyrics album band playlist paint drawing photography art sculpture gallery exhibition spotify ; musica canzone chitarra pianoforte testo album fotografia arte disegno pittura scultura mostra spotify

# ───────────────────────── Entertainment & media ─────────────────────────
media > - | Entertainment | Intrattenimento | movie movies film show series tv watchlist watch_list podcast game games gaming concert theatre stream youtube entertainment ; film serie televisione guardare podcast gioco giochi concerto teatro intrattenimento youtube
movies_tv > media | Movies & TV | Film e serie | movie movies tv series season episode netflix cinema trailer director actor documentary anime hbo disney binge imdb ; film serie stagione episodio cinema regista attore documentario anime netflix
games > media | Games | Giochi | videogame playstation xbox nintendo steam level boss board_game chess puzzle multiplayer ; videogioco console livello gioco_da_tavolo scacchi puzzle multigiocatore
sports > media,health | Sports | Sport | football soccer basketball tennis golf match ~team score tournament league f1 formula_one ski skiing padel volleyball ; calcio pallacanestro basket tennis golf partita ~squadra torneo campionato sci padel pallavolo
hobbies > media | Hobbies | Hobby | hobby knitting woodworking collecting crafts model drone fishing camping photography_hobby pottery gardening_hobby ; hobby maglia falegnameria collezione artigianato modellismo drone pesca campeggio ceramica

# ───────────────────────── Personal growth ─────────────────────────
personal@0.8 > - | Personal Growth | Crescita personale | goal goals habit habits routine journal diary reflection resolution priorities mindset motivation growth self_improvement productivity ; obiettivo obiettivi abitudine abitudini routine diario riflessione proposito priorità mentalità motivazione crescita miglioramento produttività
goals_habits > personal | Goals & habits | Obiettivi e abitudini | target milestone_goal streak okr vision_board new_years_resolution daily_habit ; traguardo serie_consecutiva okr buoni_propositi abitudine_quotidiana
journal > personal | Journal | Diario | i_felt ~felt ~feeling mood grateful reflect entry dear_diary today_i ; mi_sono_sentito mi_sento umore grato riflettere pagina_di_diario oggi_ho
quotes > personal,ideas | Quotes | Citazioni | quote quotation saying proverb wisdom said_that ; citazione detto proverbio saggezza

# ───────────────────────── Admin & documents ─────────────────────────
admin@0.9 > - | Admin & Documents | Documenti e pratiche | document paperwork form application !renew !renewal license id permit certificate legal official registration office bureaucracy ; documento pratica modulo domanda !rinnovare !rinnovo patente carta_identità permesso certificato legale ufficiale registrazione burocrazia
appointments > admin | Appointments | Appuntamenti | ~appointment booking_slot reschedule confirm_booking calendar_slot ; ~appuntamento fissare spostare_appuntamento conferma_prenotazione
vehicle > admin,home | Car & vehicle | Auto e veicoli | car vehicle oil_change tire mechanic mot inspection fuel parking parking_ticket license_plate scooter motorbike garage road_tax ; auto macchina tagliando gomme meccanico revisione benzina parcheggio multa targa scooter moto officina bollo
legal > admin | Legal | Legale | contract lawyer court lease signature notary will power_of_attorney terms_and_conditions agreement nda ; contratto avvocato tribunale locazione firma notaio testamento procura accordo
''';
