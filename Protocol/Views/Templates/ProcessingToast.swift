
import SwiftUI

struct ProcessingToast: View {
    @ObservedObject var service: RetirementService
    
    var body: some View {
        HStack(spacing: 12) {
            if service.isProcessing {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(service.isProcessing ? "Processing Retirement" : "Retirement Complete")
                    .font(.subheadline.weight(.semibold))
                
                Text(service.processingStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if service.isProcessing && service.processingProgress > 0 {
                    ProgressView(value: service.processingProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 150)
                }
            }
            
            if service.isProcessing {
                Spacer()
                Button("Cancel") {
                    service.cancelProcessing()
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 8)
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(), value: service.isProcessing)
    }
}
