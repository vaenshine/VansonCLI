/**
 * VCMermaidPreviewView -- native inline preview for Mermaid diagrams
 */

#import <UIKit/UIKit.h>

@interface VCMermaidPreviewView : UIView

- (void)configureWithTitle:(NSString *)title
                   summary:(NSString *)summary
                   content:(NSString *)content
               diagramType:(NSString *)diagramType;

@end
