# Khatabook-style Accounting App

Flutter starter implementation based on the supplied ledger/report screenshot.

## Included
- Multiple businesses
- Separate Customers and Suppliers
- A-Z alphabetical sorting
- Customer receivable and supplier payable totals
- Khatabook-style ledger/report screen
- Add payment/credit entries
- Multiple bill-photo attachment flow
- WhatsApp/share action
- Excel export/import
- Local persistence with SharedPreferences
- Firebase-ready services and dependency setup

## Firebase setup
1. Install Flutter and Android Studio.
2. Run `flutter pub get`.
3. Create a Firebase project.
4. Run `flutterfire configure`.
5. Enable Authentication, Firestore and Storage.
6. Replace the demo/local repository with FirebaseRepository where required.
7. Build with `flutter run`.

The generated source deliberately does not contain Firebase credentials.

## Data model
Business
  -> contacts (customer/supplier)
  -> transactions
  -> bill photos

Transaction:
date, description, type, amount, balanceAfter, billPaths

For customers:
  YOU GAVE = amount owed by customer
  YOU GOT  = payment received from customer

For suppliers:
  YOU GAVE = payment made to supplier
  YOU GOT  = amount payable/purchase credited to supplier

The UI keeps customer and supplier totals separate.


## Build APK without Android Studio

This project includes GitHub Actions at `.github/workflows/build-apk.yml`.

1. Create a GitHub repository.
2. Upload all project files to the repository.
3. Open **Actions**.
4. Select **Build Android APK**.
5. Click **Run workflow**.
6. Wait for the green check mark.
7. Open the completed workflow run.
8. Under **Artifacts**, download `my-khata-release-apk`.
9. Extract the downloaded artifact ZIP and install `app-release.apk` on Android.

No Android Studio is required on your computer.

Important: Firebase cloud sync requires your Firebase Android configuration (`google-services.json`) and Firebase project setup before that part can work. The basic local APK build does not require your own Firebase credentials.
