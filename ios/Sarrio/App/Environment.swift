import SwiftUI

extension EnvironmentValues {
    @Entry var apiClient: APIClient = APIClient(baseURL: AppConfig.apiBaseURL)
    @Entry var peakPackStore: PeakPackStore = PeakPackStore(api: APIClient(baseURL: AppConfig.apiBaseURL))
}
