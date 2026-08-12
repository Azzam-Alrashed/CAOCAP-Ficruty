import Testing
import Foundation
@testable import caocap

struct ProjectTemplateProviderTests {
    
    @Test func templateEnumCasesHaveValidProperties() {
        for template in ProjectTemplate.allCases {
            #expect(!template.id.isEmpty)
            #expect(!template.displayName.isEmpty)
            #expect(!template.description.isEmpty)
            #expect(!template.icon.isEmpty)
        }
    }
    
    @Test func defaultTemplateStartsWithCleanCanvas() {
        let nodes = ProjectTemplateProvider.nodes(for: .helloWorld)
        #expect(nodes.isEmpty)
    }

    @Test func defaultMiniAppCodeIsEmptyPlaceholder() {
        #expect(ProjectTemplateProvider.defaultCode.isEmpty)
    }
}
