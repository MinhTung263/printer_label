//
//  SelectDevice.swift
//  Pods
//
//  Created by Whis on 7/2/25.
//

import UIKit
import PrinterSDK
import UIKit
import Flutter
class SelectDevice: UIViewController, UITableViewDelegate, UITableViewDataSource {
    static let shared = SelectDevice()
    var tableView = UITableView()
    var dataSources: [PTPrinter] = []
    var onPrinterSelected: ((PTPrinter) -> Void)?
    var onPrintersUpdated: (([PTPrinter]) -> Void)?
    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
    }
    
    func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.frame = view.bounds
        view.addSubview(tableView)
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        PTDispatcher.share()?.unconnectBlock = nil
        PTDispatcher.share().scanBluetooth()
        
        PTDispatcher.share()?.whenFindAllBluetooth({ [weak self] in
            guard let self = self else { return }
            guard let temp = $0 as? [PTPrinter] else { return }
            self.dataSources = temp.sorted(by: { $0.distance.floatValue < $1.distance.floatValue })
            self.tableView.reloadData()
        })
        
    }
    
    // UITableView DataSource Methods
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataSources.count
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let selectedPrinter = dataSources[indexPath.row]
        onPrinterSelected?(selectedPrinter)
        onPrintersUpdated?(dataSources)
        self.dismiss(animated: true, completion: nil)
        
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        let printer = dataSources[indexPath.row]
        cell.textLabel?.text = printer.name ?? "Unknown Printer"
        cell.detailTextLabel?.text = "Distance: \(printer.distance.floatValue)"
        return cell
    }
    
}



