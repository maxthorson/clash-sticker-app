/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
MessagesViewController displays the custom collection of MSStickers.
*/

import UIKit
import Messages

class MessagesViewController: MSMessagesAppViewController {
    
    private var collectionView: UICollectionView!
    private var datasource: UICollectionViewDiffableDataSource<String, MSSticker>!
    
    private static var fiveItemSection: NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.2), heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(60))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 10
        return section
    }
    
    // Creates a custom layout using section providers.
    private static func createLayout() -> UICollectionViewLayout {
        let sectionProvider = { (sectionIndex: Int, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in
            let headerFooterSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(44))
            let section = MessagesViewController.fiveItemSection
            let titleSectionHeader = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerFooterSize, elementKind: TitleSupplementaryView.reuseIdentifier, alignment: .topLeading)
            section.boundarySupplementaryItems = [titleSectionHeader]
            return section
        }
        return UICollectionViewCompositionalLayout(sectionProvider: sectionProvider)
    }
    
    private func setupCollection() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: MessagesViewController.createLayout())
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, MSSticker> { (cell, indexPath, item) in
            cell.contentConfiguration = CustomContentConfiguration(sticker: item)
        }
        
        datasource = UICollectionViewDiffableDataSource<String, MSSticker>(
            collectionView: collectionView, cellProvider: { (collectionView, indexPath, item) -> UICollectionViewCell? in
                return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
            }
        )
        
        let titleHeaderRegistration = UICollectionView.SupplementaryRegistration
        <TitleSupplementaryView>(elementKind: TitleSupplementaryView.reuseIdentifier) {
            (supplementaryView, string, indexPath) in
            let sections = self.datasource.snapshot().sectionIdentifiers
            if indexPath.section < sections.count {
                supplementaryView.label.text = sections[indexPath.section]
            } else {
                supplementaryView.label.text = ""
            }
        }
        
        datasource.supplementaryViewProvider = { (view, kind, index) in
            return self.collectionView.dequeueConfiguredReusableSupplementary(
                using: titleHeaderRegistration, for: index)
        }
    }
    
    private func populateCollection() {
        var snapshot = NSDiffableDataSourceSnapshot<String, MSSticker>()
        let categories = loadCategoriesFromPlist()

        for category in categories {
            let targetMaxPixels: CGFloat = 300
            let stickers: [MSSticker] = category.images.compactMap { name in
                // Allow filenames with or without extension (default to png)
                let resource: String
                let ext: String
                if let dotRange = name.range(of: ".", options: .backwards) {
                    resource = String(name[..<dotRange.lowerBound])
                    ext = String(name[dotRange.upperBound...])
                } else {
                    resource = name
                    ext = "png"
                }
                guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else { return nil }
                // If it's a PNG, try to downscale; otherwise use the original
                if ext.lowercased() == "png", let scaledURL = resizedPNG(from: url, maxPixel: targetMaxPixels) {
                    return try? MSSticker(contentsOfFileURL: scaledURL, localizedDescription: resource)
                } else {
                    return try? MSSticker(contentsOfFileURL: url, localizedDescription: resource)
                }
            }
            snapshot.appendSections([category.title])
            snapshot.appendItems(stickers, toSection: category.title)
        }

        datasource.apply(snapshot, animatingDifferences: true, completion: nil)
    }
    
    private func loadCategoriesFromPlist() -> [(title: String, images: [String])] {
        // Expects a Categories.plist with root Array of dicts: { "title": String, "images": [String] }
        guard let url = Bundle.main.url(forResource: "Categories", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let array = plist as? [[String: Any]] else {
            return []
        }
        return array.compactMap { dict in
            guard let title = dict["title"] as? String,
                  let images = dict["images"] as? [String] else { return nil }
            return (title: title, images: images)
        }
    }
    
    private func resizedPNG(from url: URL, maxPixel: CGFloat) -> URL? {
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }

        // Keep aspect ratio; cap the longest side to maxPixel, never upscale
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(maxPixel / longestSide, 1)
        let newSize = CGSize(width: floor(image.size.width * scale),
                             height: floor(image.size.height * scale))

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        guard let pngData = scaled.pngData() else { return nil }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        do {
            try pngData.write(to: tmp, options: [.atomic])
            return tmp
        } catch {
            return nil
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setupCollection()
        populateCollection()
    }

}

extension MessagesViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let convo = activeConversation, let sticker = datasource.itemIdentifier(for: indexPath) {
            convo.insert(sticker, completionHandler: nil)
        }
    }
}
