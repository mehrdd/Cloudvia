//
//  CloudviaApp.swift
//  Cloudvia
//
//  Created by Mehrdad Nassiri.
//

import SwiftUI

// MARK: - Models
struct Account: Identifiable, Codable, Hashable {
    let id: String
    let name: String
}

struct Zone: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let account: Account

    enum CodingKeys: String, CodingKey {
        case id, name, account
    }
}

struct DNSRecord: Identifiable, Decodable, Hashable {
    let id: String
    let type: String
    let name: String
    let content: String
    let proxied: Bool
}

struct CloudflareAccountsResponse: Decodable {
    let result: [Account]
}

struct CloudflareZonesResponse: Decodable {
    let result: [Zone]
}

struct CloudflareDNSRecordsResponse: Decodable {
    let result: [DNSRecord]
}

struct CloudflarePurgeCacheResponse: Decodable {
    let success: Bool
    let errors: [String]
    let messages: [String]
    let result: [String: String]

    enum CodingKeys: String, CodingKey {
        case success, errors, messages, result
    }
}

// MARK: - ViewModel
class CloudviaViewModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var zones: [Zone] = []
    @Published var records: [DNSRecord] = []
    @Published var selectedAccount: String = "All Accounts"
    @Published var selectedZone: Zone? = nil
    @Published var showAddRecordSheet = false
    @Published var showDeleteConfirmation = false
    @Published var recordToDelete: DNSRecord? = nil
    @Published var editingRecord: DNSRecord? = nil
    @Published var zoneFilter = ""
    @Published var recordFilter = ""
    @Published var isSearchFieldVisible = false
    @Published var isLoadingAccounts = false
    @Published var isLoadingZones = false
    @Published var isLoadingRecords = false
    @Published var apiValidationResult: (isValid: Bool, message: String)? = nil
    @Published var showCachePurgeSheet = false
    @Published var purgeType: PurgeType = .everything
    @Published var purgeResult: (isSuccess: Bool, message: String)? = nil
    @Published var isPurging = false
    @Published var newRecordName = ""
    @Published var newRecordContent = ""
    @Published var newRecordProxied = false
    @Published var newRecordType = "A"

    @AppStorage("apiEmail") var apiEmail: String = "" // تغییر به var برای دسترسی
    @AppStorage("apiKey") var apiKey: String = ""
    @AppStorage("cachedUrls") var cachedUrls: String = ""

    var configuredEmail: String {
        apiEmail
    }
    
    func logout() {
        apiEmail = ""
        apiKey = ""
        accounts = []
        zones = []
        records = []
        selectedAccount = "All Accounts"
        selectedZone = nil
        apiValidationResult = nil
    }

    enum PurgeType: String, CaseIterable {
        case everything = "Purge Everything"
        case custom = "Custom page URL"
    }

    var filteredZones: [Zone] {
        var filtered = zones
        if selectedAccount != "All Accounts" {
            filtered = filtered.filter { $0.account.id == selectedAccount }
        }
        if !zoneFilter.isEmpty {
            filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(zoneFilter) }
        }
        return filtered
    }

    var filteredRecords: [DNSRecord] {
        recordFilter.isEmpty ? records : records.filter {
            $0.name.localizedCaseInsensitiveContains(recordFilter) ||
            $0.content.localizedCaseInsensitiveContains(recordFilter)
        }
    }

    var isApiConfigured: Bool {
        !apiEmail.isEmpty && !apiKey.isEmpty
    }

    func sortRecords<T: Comparable>(by keyPath: KeyPath<DNSRecord, T>, ascending: Bool) {
        records.sort { record1, record2 in
            let value1 = record1[keyPath: keyPath]
            let value2 = record2[keyPath: keyPath]
            return ascending ? value1 < value2 : value1 > value2
        }
    }

    func sortRecordsByProxied(ascending: Bool) {
        records.sort { record1, record2 in
            if record1.proxied == record2.proxied { return false }
            return ascending ? record1.proxied : !record1.proxied
        }
    }

    func fetchAccounts() {
        guard isApiConfigured else { return }
        guard let url = URL(string: "https://api.cloudflare.com/client/v4/accounts?per_page=1000") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiEmail, forHTTPHeaderField: "X-Auth-Email")
        request.setValue(apiKey, forHTTPHeaderField: "X-Auth-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        DispatchQueue.main.async {
            self.isLoadingAccounts = true
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoadingAccounts = false
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                   let data = data,
                   let decoded = try? JSONDecoder().decode(CloudflareAccountsResponse.self, from: data) {
                    self.accounts = decoded.result
                    self.apiValidationResult = (true, "API credentials are valid")
                } else {
                    self.apiValidationResult = (false, "Invalid API credentials. Please check and try again.")
                }
            }
        }.resume()
    }

    func fetchZones() {
        guard isApiConfigured else { return }
        guard let url = URL(string: "https://api.cloudflare.com/client/v4/zones?per_page=1000") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiEmail, forHTTPHeaderField: "X-Auth-Email")
        request.setValue(apiKey, forHTTPHeaderField: "X-Auth-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        DispatchQueue.main.async {
            self.isLoadingZones = true
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoadingZones = false
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                   let data = data,
                   let decoded = try? JSONDecoder().decode(CloudflareZonesResponse.self, from: data) {
                    self.zones = decoded.result
                    self.apiValidationResult = (true, "API credentials are valid")
                } else {
                    self.apiValidationResult = (false, "Invalid API credentials. Please check and try again.")
                }
            }
        }.resume()
    }

    func fetchDNSRecords() {
        guard isApiConfigured, let zone = selectedZone else { return }
        guard let url = URL(string: "https://api.cloudflare.com/client/v4/zones/\(zone.id)/dns_records") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiEmail, forHTTPHeaderField: "X-Auth-Email")
        request.setValue(apiKey, forHTTPHeaderField: "X-Auth-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        DispatchQueue.main.async {
            self.isLoadingRecords = true
        }

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let decoded = try? JSONDecoder().decode(CloudflareDNSRecordsResponse.self, from: data) else {
                DispatchQueue.main.async {
                    self.isLoadingRecords = false
                }
                return
            }
            DispatchQueue.main.async {
                self.records = decoded.result
                self.isLoadingRecords = false
            }
        }.resume()
    }

    func saveRecord() {
        guard isApiConfigured, let zone = selectedZone else { return }
        let isEditing = editingRecord != nil
        let urlStr = isEditing ?
            "https://api.cloudflare.com/client/v4/zones/\(zone.id)/dns_records/\(editingRecord!.id)" :
            "https://api.cloudflare.com/client/v4/zones/\(zone.id)/dns_records"

        guard let url = URL(string: urlStr) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = isEditing ? "PUT" : "POST"
        request.setValue(apiEmail, forHTTPHeaderField: "X-Auth-Email")
        request.setValue(apiKey, forHTTPHeaderField: "X-Auth-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "type": newRecordType,
            "name": newRecordName,
            "content": newRecordContent,
            "proxied": newRecordProxied
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                self.fetchDNSRecords()
                self.showAddRecordSheet = false
            }
        }.resume()
    }

    func deleteRecord(_ record: DNSRecord) {
        guard isApiConfigured, let zone = selectedZone else { return }
        guard let url = URL(string: "https://api.cloudflare.com/client/v4/zones/\(zone.id)/dns_records/\(record.id)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(apiEmail, forHTTPHeaderField: "X-Auth-Email")
        request.setValue(apiKey, forHTTPHeaderField: "X-Auth-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                self.fetchDNSRecords()
            }
        }.resume()
    }

    func purgeCache(urls: String) {
        guard isApiConfigured, let zone = selectedZone else { return }
        guard let url = URL(string: "https://api.cloudflare.com/client/v4/zones/\(zone.id)/purge_cache") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiEmail, forHTTPHeaderField: "X-Auth-Email")
        request.setValue(apiKey, forHTTPHeaderField: "X-Auth-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any]
        if purgeType == .everything {
            body = ["purge_everything": true]
        } else {
            let urlList = urls.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !urlList.isEmpty else {
                DispatchQueue.main.async {
                    self.purgeResult = (false, "Please enter at least one valid URL.")
                }
                return
            }
            body = ["files": urlList]
            cachedUrls = urls
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        DispatchQueue.main.async {
            self.isPurging = true
            self.purgeResult = nil
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isPurging = false
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                   let data = data,
                   let decoded = try? JSONDecoder().decode(CloudflarePurgeCacheResponse.self, from: data),
                   decoded.success {
                    self.purgeResult = (true, "Cache purged successfully.")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.showCachePurgeSheet = false
                        self.purgeResult = nil
                    }
                } else {
                    let errorMessage = error?.localizedDescription ?? "Failed to purge cache. Please try again."
                    self.purgeResult = (false, errorMessage)
                }
            }
        }.resume()
    }

    func resetRecordForm() {
        editingRecord = nil
        newRecordName = ""
        newRecordContent = ""
        newRecordType = "A"
        newRecordProxied = false
    }

    func editRecord(_ record: DNSRecord) {
        editingRecord = record
        newRecordName = record.name
        newRecordContent = record.content
        newRecordProxied = record.proxied
        newRecordType = record.type
        showAddRecordSheet = true
    }

    func validateApiCredentials(email: String, key: String, completion: @escaping (Bool, String) -> Void) {
        guard !email.isEmpty, !key.isEmpty else {
            completion(false, "API email and key are required.")
            return
        }
        guard let url = URL(string: "https://api.cloudflare.com/client/v4/zones?per_page=1") else {
            completion(false, "Invalid API URL.")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(email, forHTTPHeaderField: "X-Auth-Email")
        request.setValue(key, forHTTPHeaderField: "X-Auth-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    completion(true, "API credentials are valid")
                } else {
                    completion(false, "Invalid API credentials. Please check and try again.")
                }
            }
        }.resume()
    }
}

struct AccountSidebar: View {
    @ObservedObject var viewModel: CloudviaViewModel
    @State private var showSettings = false
    @State private var showLogoutConfirmation = false // برای دیالوگ تأیید

    var body: some View {
        VStack {
            if viewModel.isLoadingAccounts {
                VStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Loading Accounts...")
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $viewModel.selectedAccount) {
                    Label("All Accounts", systemImage: "folder")
                        .foregroundColor(.primary)
                        .accentColor(.secondary)
                        .tag("All Accounts")
                        .padding(.vertical, 2)
                    ForEach(viewModel.accounts) { account in
                        Label(account.name, systemImage: "folder")
                            .foregroundColor(.primary)
                            .accentColor(.secondary)
                            .tag(account.id)
                            .padding(.vertical, 2)
                    }
                }
                Spacer()
                Button(action: {
                    showSettings = true
                }) {
                    HStack {
                        Image(systemName: "person.circle")
                            .font(.system(size: 16))
                        Text(viewModel.isApiConfigured ? viewModel.configuredEmail : "Configure Account")
                            .font(.system(size: 14))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.windowBackgroundColor))
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .contextMenu {
                    if viewModel.isApiConfigured {
                        Button("Settings") {
                            showSettings = true
                        }
                        Button("Logout", role: .destructive) {
                            showLogoutConfirmation = true
                        }
                    }
                }
                .confirmationDialog(
                    "Are you sure you want to logout?",
                    isPresented: $showLogoutConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Logout", role: .destructive) {
                        viewModel.logout()
                    }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView(viewModel: viewModel)
                }
            }
        }
        .frame(minWidth: 150)
    }
}

struct CustomButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(6)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.windowBackgroundColor))
                    .shadow(radius: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

struct ZoneSidebar: View {
    @ObservedObject var viewModel: CloudviaViewModel

    var body: some View {
        VStack {
            HStack {
                TextField("Search zones", text: $viewModel.zoneFilter)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.windowBackgroundColor))
                            .shadow(radius: 1)
                    )
                    .frame(maxWidth: .infinity)
                Button(action: {
                    viewModel.fetchZones()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .regular))
                }
                .help("Refresh zones")
                .buttonStyle(CustomButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            if viewModel.isLoadingZones {
                VStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Loading Zones...")
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.filteredZones, selection: $viewModel.selectedZone) { zone in
                    Text(zone.name)
                        .tag(zone)
                        .padding(.vertical, 2)
                }
            }
        }
        .frame(minWidth: 200)
        .onChange(of: viewModel.selectedZone) { _, _ in
            viewModel.resetRecordForm()
            viewModel.fetchDNSRecords()
        }
        .onChange(of: viewModel.selectedAccount) { _, _ in
            viewModel.selectedZone = nil
            viewModel.records = []
        }
        .onAppear {
            viewModel.fetchAccounts()
            viewModel.fetchZones()
        }
    }
}

struct CachePurgeSheet: View {
    @ObservedObject var viewModel: CloudviaViewModel
    @State private var urls: String
    @Environment(\.dismiss) private var dismiss

    init(viewModel: CloudviaViewModel) {
        self.viewModel = viewModel
        self._urls = State(initialValue: viewModel.cachedUrls)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Purge Cache")
                .font(.headline)
                .padding(.bottom, 5)

            Picker("Purge Type", selection: $viewModel.purgeType) {
                ForEach(CloudviaViewModel.PurgeType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 5)

            if viewModel.purgeType == .custom {
                Text("Enter URLs (one per line):")
                    .font(.subheadline)
                TextEditor(text: $urls)
                    .frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray, lineWidth: 1))
                    .padding(.bottom, 5)
            }

            if let result = viewModel.purgeResult {
                HStack {
                    Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.isSuccess ? .green : .red)
                    Text(result.message)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 5)
            }

            HStack {
                Button("Close", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Purge") {
                    viewModel.purgeCache(urls: urls)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isPurging || (viewModel.purgeType == .custom && urls.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding()
        .frame(width: 400, height: viewModel.purgeType == .custom ? 300 : 180)
        .background(.background)
    }
}

struct AddRecordSheet: View {
    @ObservedObject var viewModel: CloudviaViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(viewModel.editingRecord == nil ? "Add DNS Record" : "Edit DNS Record")
                .font(.headline)
                .padding(.bottom, 5)
            HStack(alignment: .center) {
                Text("Name:")
                    .frame(width: 80, alignment: .trailing)
                TextField("e.g., example.com", text: $viewModel.newRecordName)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(alignment: .center) {
                Text("Content:")
                    .frame(width: 80, alignment: .trailing)
                TextField("e.g., 192.0.2.1", text: $viewModel.newRecordContent)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(alignment: .center) {
                Text("Type:")
                    .frame(width: 80, alignment: .trailing)
                Picker("Type", selection: $viewModel.newRecordType) {
                    Text("A").tag("A")
                    Text("CNAME").tag("CNAME")
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            HStack(alignment: .center) {
                Text("Proxied:")
                    .frame(width: 80, alignment: .trailing)
                Toggle("Proxied", isOn: $viewModel.newRecordProxied)
                    .labelsHidden()
            }
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    viewModel.saveRecord()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.newRecordName.isEmpty || viewModel.newRecordContent.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 220)
        .background(.background)
    }
}

struct RecordsTable: View {
    @ObservedObject var viewModel: CloudviaViewModel
    @State private var selectedRecordID: DNSRecord.ID? = nil

    var body: some View {
        Table(viewModel.filteredRecords, selection: $selectedRecordID) {
            TableColumn("Type") { record in
                Text(record.type)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 50, ideal: 70)

            TableColumn("Name") { record in
                Text(record.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 150, ideal: 200)

            TableColumn("Content") { record in
                Text(record.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 150, ideal: 300)

            TableColumn("Proxied") { record in
                Text(record.proxied ? "✅" : "❌")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 70, ideal: 70)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu(forSelectionType: DNSRecord.ID.self) { recordIDs in
            if let recordID = recordIDs.first,
               let record = viewModel.filteredRecords.first(where: { $0.id == recordID }) {
                Button("Edit") {
                    viewModel.editRecord(record)
                }
                Button("Delete", role: .destructive) {
                    viewModel.recordToDelete = record
                    viewModel.showDeleteConfirmation = true
                }
            }
        }
        .onTapGesture(count: 2) {
            if let recordID = selectedRecordID,
               let record = viewModel.filteredRecords.first(where: { $0.id == recordID }) {
                viewModel.editRecord(record)
            }
        }
    }
}

struct SettingsView: View {
    @AppStorage("apiEmail") private var apiEmail: String = ""
    @AppStorage("apiKey") private var apiKey: String = ""
    @State private var tempApiEmail: String = ""
    @State private var tempApiKey: String = ""
    @State private var isValidating = false
    @State private var showValidationResult = false
    @State private var validationResult: (isValid: Bool, message: String)? = nil
    @State private var isValidated = false
    @State private var showLogoutConfirmation = false
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: CloudviaViewModel

    var body: some View {
        Form {
            // هدر و دکمه Logout
            HStack {
                Text("Cloudflare API Credentials")
                    .font(.headline)
                Spacer()
                if viewModel.isApiConfigured {
                    Button(action: {
                        showLogoutConfirmation = true
                    }) {
                        Image(systemName: "arrow.right.square")
                            .font(.system(size: 14))
                        Text("Logout")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                    .confirmationDialog(
                        "Are you sure you want to logout?",
                        isPresented: $showLogoutConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Logout", role: .destructive) {
                            viewModel.logout()
                            dismiss()
                        }
                    }
                }
            }
            .padding(.bottom, 10)

            // فیلدهای ورودی
            HStack {
                Text("API Email:")
                    .frame(width: 100, alignment: .trailing)
                TextField("", text: $tempApiEmail)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
            }
            HStack {
                Text("API Key:")
                    .frame(width: 100, alignment: .trailing)
                SecureField("", text: $tempApiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
            }

            // نتیجه اعتبارسنجی
            if showValidationResult, let result = validationResult {
                HStack {
                    Image(systemName: result.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.isValid ? .green : .red)
                    Text(result.message)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 5)
            }

            // دکمه‌های Cancel و Save/Validate
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
                
                Button(isValidated ? "Save" : "Validate") {
                    if isValidated {
                        apiEmail = tempApiEmail
                        apiKey = tempApiKey
                        viewModel.fetchAccounts()
                        viewModel.fetchZones()
                        isValidated = false
                        showValidationResult = false
                        validationResult = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            dismiss()
                        }
                    } else {
                        isValidating = true
                        viewModel.validateApiCredentials(email: tempApiEmail, key: tempApiKey) { isValid, message in
                            validationResult = (isValid, message)
                            showValidationResult = true
                            isValidated = isValid
                            isValidating = false
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tempApiEmail.isEmpty || tempApiKey.isEmpty || isValidating)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 10)
        }
        .padding()
        .frame(width: 400, height: 220)
        .onAppear {
            tempApiEmail = apiEmail
            tempApiKey = apiKey
            isValidated = false
            showValidationResult = false
            validationResult = nil
        }
        .onChange(of: tempApiEmail) { _, _ in
            if isValidated {
                isValidated = false
                showValidationResult = false
            }
        }
        .onChange(of: tempApiKey) { _, _ in
            if isValidated {
                isValidated = false
                showValidationResult = false
            }
        }
    }
}

struct ContentView: View {
    @StateObject var viewModel = CloudviaViewModel()
    @State private var showSettings = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var windowTitle: String = "Cloudvia"

    var body: some View {
        if !viewModel.isApiConfigured {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .foregroundColor(.orange)
                Text("API Configuration Required")
                    .font(.headline)
                Text("Please configure your Cloudflare API email and key in Settings.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    showSettings = true
                }
                .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
            }
        } else {
            NavigationSplitView {
                AccountSidebar(viewModel: viewModel)
            } content: {
                ZoneSidebar(viewModel: viewModel)
            } detail: {
                if viewModel.selectedZone != nil {
                    VStack(spacing: 0) {
                        ZStack {
                            if viewModel.isLoadingRecords {
                                VStack {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                    Text("Loading DNS Records...")
                                        .foregroundColor(.secondary)
                                        .padding(.top, 8)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                RecordsTable(viewModel: viewModel)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .disabled(viewModel.isLoadingRecords)
                        Text("\(viewModel.filteredRecords.count) records")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5))
                    }
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Spacer()
                        }
                        
                        ToolbarItem(placement: .confirmationAction) {
                            Button(action: {
                                viewModel.fetchDNSRecords()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .help("Refresh DNS records")
                            .keyboardShortcut("r", modifiers: .command)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(action: {
                                viewModel.resetRecordForm()
                                viewModel.showAddRecordSheet = true
                            }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .help("Add a new DNS record")
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(action: {
                                viewModel.showCachePurgeSheet = true
                            }) {
                                Image(systemName: "externaldrive.badge.xmark")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .help("Purge cache")
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(action: {
                                withAnimation {
                                    viewModel.isSearchFieldVisible.toggle()
                                    if viewModel.isSearchFieldVisible {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            isSearchFieldFocused = true
                                        }
                                    }
                                }
                            }) {
                                Image(systemName: viewModel.isSearchFieldVisible ? "xmark.circle" : "magnifyingglass")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .help(viewModel.isSearchFieldVisible ? "Hide search" : "Search records")
                            .keyboardShortcut("f", modifiers: .command)
                        }
                        ToolbarItem(placement: .automatic) {
                            if viewModel.isSearchFieldVisible {
                                TextField("Search records", text: $viewModel.recordFilter)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 200)
                                    .focused($isSearchFieldFocused)
                                    .onSubmit {
                                        viewModel.isSearchFieldVisible = false
                                    }
                            }
                        }
                    }
                    .confirmationDialog(
                        "Are you sure you want to delete this record?",
                        isPresented: $viewModel.showDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            if let record = viewModel.recordToDelete {
                                viewModel.deleteRecord(record)
                            }
                        }
                    }
                    .sheet(isPresented: $viewModel.showAddRecordSheet) {
                        AddRecordSheet(viewModel: viewModel)
                    }
                    .sheet(isPresented: $viewModel.showCachePurgeSheet) {
                        CachePurgeSheet(viewModel: viewModel)
                    }
                } else {
                    VStack {
                        Image(systemName: "globe")
                            .resizable()
                            .frame(width: 64, height: 64)
                            .foregroundColor(.secondary)
                        Text("Please select a zone")
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(windowTitle)
            .onChange(of: viewModel.selectedZone) { _, newZone in
                windowTitle = newZone?.name ?? "Cloudvia"
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSEventEscKey)) { _ in
                if viewModel.isSearchFieldVisible {
                    viewModel.isSearchFieldVisible = false
                    isSearchFieldFocused = false
                }
            }
            .onAppear {
                viewModel.selectedAccount = "All Accounts"
            }
        }
    }
}

// Extension to handle Esc key
extension Notification.Name {
    static let NSEventEscKey = Notification.Name("NSEventEscKey")
}

// Custom NSEvent handler for Esc key
class EscKeyHandler: NSObject {
    static let shared = EscKeyHandler()
    
    private override init() {
        super.init()
        
        #if os(macOS)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                NotificationCenter.default.post(name: .NSEventEscKey, object: nil)
                return nil
            }
            return event
        }
        #elseif os(iOS)
        let escCommand = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(handleEscKey))
        UIApplication.shared.windows.first?.rootViewController?.addKeyCommand(escCommand)
        #endif
    }
    
    #if os(iOS)
    @objc private func handleEscKey() {
        NotificationCenter.default.post(name: .NSEventEscKey, object: nil)
    }
    #endif
}

struct AboutView: View {
    var body: some View {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .cornerRadius(16)
                .padding(.top, 20)

            Text("Cloudvia")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(appVersion)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()
                .padding(.vertical, 8)

            VStack(spacing: 8) {
                Link("Website", destination: URL(string: "https://github.com/mehrdd/Cloudvia")!)
                Link("Support Email", destination: URL(string: "mailto:cloudvia@vandaw.com")!)
            }
            .font(.body)

            Spacer()
        }
        .frame(width: 300, height: 350)
        .padding()
    }
}
