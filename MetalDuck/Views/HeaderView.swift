//
//  HeaderView.swift
//  MetalDuck
//
//  Created by Roberto Camargo on 07/11/25.
//

import SwiftUI

/// A view that displays a styled header for sections.
struct HeaderView: View {
    
    private let title: String
    private let alignmentOffset: CGFloat = 10.0
    
    init(_ title: String) {
        self.title = title
    }
    
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.secondary)
            .alignmentGuide(.leading) { _ in alignmentOffset }
    }
}

