//
//  WXMapViewComponent.m
//  WeexDemo
//
//  Created by yangshengtao on 2017/1/20.
//  Copyright © 2016年 taobao. All rights reserved.
//

#import "WXMapViewComponent.h"
#import "WXMapViewMarkerComponent.h"
#import "WXMapPolylineComponent.h"
#import "WXMapPolygonComponent.h"
#import "WXMapCircleComponent.h"
#import "WXMapInfoWindowComponent.h"
#import "WXMapCustomInfoWindow.h"
#import "WXImgLoaderImpl.h"
#import "NSArray+WXMap.h"
#import "NSDictionary+WXMap.h"
#import "WXConvert+AMapKit.h"
#import <objc/runtime.h>

@interface MAPointAnnotation(imageAnnotation)

@property(nonatomic, copy) NSString *iconImage;
@property(nonatomic, strong) WXComponent *component;

@end

static const void *iconImageKey = &iconImageKey;
static const void *componentAnnotationKey = &componentAnnotationKey;

@implementation MAPointAnnotation (imageAnnotation)

@dynamic iconImage;

- (void)setIconImage:(NSString *)iconImage
{
    objc_setAssociatedObject(self, iconImageKey, iconImage, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (NSString *)iconImage
{
    return objc_getAssociatedObject(self, iconImageKey);
}

- (void)setComponent:(WXComponent *)component
{
    objc_setAssociatedObject(self, componentAnnotationKey, component, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (WXComponent *)component
{
    return objc_getAssociatedObject(self, componentAnnotationKey);
}

@end

@interface MAShape(WXMapShape)

@property(nonatomic, strong) WXComponent *component;

@end

static const void *componentKey = &componentKey;

@implementation MAShape(WXMapShape)

@dynamic component;

- (void)setComponent:(WXComponent *)component {
    objc_setAssociatedObject(self, componentKey, component, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (WXComponent *)component {
    return objc_getAssociatedObject(self, componentKey);
}

@end


@interface WXMapViewComponent()

@property (nonatomic, strong) MAMapView *mapView;

@end

@implementation WXMapViewComponent
{
    CLLocationCoordinate2D _centerCoordinate;
    NSMutableDictionary *_annotations;
    CGFloat _zoomLevel;
    BOOL _showScale;
    BOOL _showGeolocation;
    BOOL _zoomChanged;
    BOOL _isDragend;
}

- (id<WXImgLoaderProtocol>)imageLoader
{
    static id<WXImgLoaderProtocol> imageLoader;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        imageLoader = [WXImgLoaderImpl new];
    });
    return imageLoader; 
}


- (instancetype)initWithRef:(NSString *)ref
                       type:(NSString*)type
                     styles:(nullable NSDictionary *)styles
                 attributes:(nullable NSDictionary *)attributes
                     events:(nullable NSArray *)events
               weexInstance:(WXSDKInstance *)weexInstance
{
    self = [super initWithRef:ref type:type styles:styles attributes:attributes events:events weexInstance:weexInstance];
    if (self) {
        NSArray *center = [attributes wxmap_safeObjectForKey:@"center"];
        _centerCoordinate.latitude = [[center wxmap_safeObjectForKey:1] doubleValue];
        _centerCoordinate.longitude = [[center wxmap_safeObjectForKey:0] doubleValue];
        _zoomLevel = [[attributes wxmap_safeObjectForKey:@"zoom"] floatValue];
        _showScale = [[attributes wxmap_safeObjectForKey:@"scale"] boolValue];
        _showGeolocation = [[attributes wxmap_safeObjectForKey:@"geolocation"] boolValue];
        if ([attributes wxmap_safeObjectForKey:@"sdkKey"]) {
            [self setAPIKey:[attributes[@"sdkKey"] objectForKey:@"ios"] ? : @""];
        }
        if ([events containsObject:@"zoomchange"]) {
            _zoomChanged = YES;
        }
        if ([events containsObject:@"dragend"]) {
            _isDragend = YES;
        }
    }
    
    return self;
}

- (UIView *) loadView
{
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    CGSize windowSize = window.rootViewController.view.frame.size;
    self.mapView = [[MAMapView alloc] initWithFrame:CGRectMake(0, 0, windowSize.width, windowSize.height)];
    self.mapView.showsUserLocation = _showGeolocation;
    self.mapView.delegate = self;
    
    return self.mapView;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.mapView.showsScale = _showScale;
    [self.mapView setCenterCoordinate:_centerCoordinate];
    [self.mapView setZoomLevel:_zoomLevel];
}


- (void)insertSubview:(WXComponent *)subcomponent atIndex:(NSInteger)index
{
    if ([subcomponent isKindOfClass:[WXMapRenderer class]]) {
        WXMapRenderer *overlayRenderer = (WXMapRenderer *)subcomponent;
        [self addOverlay:overlayRenderer];
    }else if ([subcomponent isKindOfClass:[WXMapViewMarkerComponent class]]) {
        [self addMarker:subcomponent];
    }
}

- (void)layoutDidFinish
{
    
}

- (void)viewWillUnload
{
    
}

- (void)dealloc
{
    [self clearPOIData];
}

- (void)updateAttributes:(NSDictionary *)attributes
{
    if (attributes[@"center"]) {
        [self setCenter:attributes[@"center"]];
    }
    
    if (attributes[@"zoom"]) {
        [self setZoomLevel:[attributes[@"zoom"] floatValue]];
    }
    
}

- (void)addEvent:(NSString *)eventName
{
    
}

- (void)removeEvent:(NSString *)eventName
{
    
}

#pragma mark - mark
- (void)addOverlay:(WXMapRenderer *)overlayRenderer
{
    MAShape *shape;
    if (!overlayRenderer.path && [overlayRenderer isKindOfClass:[WXMapCircleComponent class]]) {
        WXMapCircleComponent *circle = (WXMapCircleComponent *)overlayRenderer;
        CLLocationCoordinate2D centerCoordinate = [WXConvert CLLocationCoordinate2D:circle.center];
        shape = [MACircle circleWithCenterCoordinate:centerCoordinate radius:circle.radius];
    }else {
        NSInteger count = overlayRenderer.path.count;
        if (count <= 0) {
            return;
        }
        CLLocationCoordinate2D shapePoints[count];
        for (NSInteger i = 0; i < count; i++) {
            CLLocationCoordinate2D coordinate = [WXConvert CLLocationCoordinate2D:[overlayRenderer.path wxmap_safeObjectForKey:i]];
            shapePoints[i].latitude = coordinate.latitude;
            shapePoints[i].longitude = coordinate.longitude;
        }
        
        if ([overlayRenderer isKindOfClass:[WXMapPolylineComponent class]]) {
            shape = [MAPolyline polylineWithCoordinates:shapePoints count:count];
        }else if ([overlayRenderer isKindOfClass:[WXMapPolygonComponent class]]) {
            shape = [MAPolygon polygonWithCoordinates:shapePoints count:count];
        }
    }
    shape.component = overlayRenderer;
    overlayRenderer.shape = shape;
    [self.mapView addOverlay:shape];
}

#pragma mark - mark
- (void)addMarker:(WXMapViewMarkerComponent *)marker {
    [self initPOIData];
    MAPointAnnotation *a1 = [[MAPointAnnotation alloc] init];
    [self convertMarker:marker onAnnotation:a1];
    [_annotations setObject:a1 forKey:marker.ref];
    [self.mapView addAnnotation:a1];
}

- (void)convertMarker:(WXMapViewMarkerComponent *)marker onAnnotation:(MAPointAnnotation *)annotation {
    if (marker.location && marker.location.count > 0) {
        annotation.coordinate = [WXConvert CLLocationCoordinate2D:marker.location];
    }
    if (marker.title) {
        annotation.title      = [NSString stringWithFormat:@"%@", marker.title];
    }
    if (marker.icon) {
        annotation.iconImage = marker.icon ? : nil;
    }
    annotation.component = marker;
}

- (void)updateTitleMarker:(WXMapViewMarkerComponent *)marker {
    MAPointAnnotation *a1 = _annotations[marker.ref];
    a1.title = [NSString stringWithFormat:@"%@", marker.title];
    [self.mapView addAnnotation:a1];
}

- (void)updateIconMarker:(WXMapViewMarkerComponent *)marker {
    MAPointAnnotation *a1 = _annotations[marker.ref];
    a1.iconImage = marker.icon ? : nil;
    [self.mapView addAnnotation:a1];
}

- (void)updateLocationMarker:(WXMapViewMarkerComponent *)marker {
    MAPointAnnotation *a1 = _annotations[marker.ref];
    CLLocationCoordinate2D coordinate;
    coordinate.latitude = [marker.location[1] doubleValue];
    coordinate.longitude = [marker.location[0] doubleValue];
    a1.coordinate = coordinate;
    [self.mapView addAnnotation:a1];
}


- (void)removeMarker:(WXMapViewMarkerComponent *)marker {
    if (_annotations[marker.ref]) {
        [self.mapView removeAnnotation:_annotations[marker.ref]];
        [_annotations removeObjectForKey:marker.ref];
    }
}


#pragma mark - component interface
- (void)setAPIKey:(NSString *)appKey
{
    [AMapServices sharedServices].apiKey = appKey;
}

- (void)setCenter:(NSArray *)center
{
    CLLocationCoordinate2D centerCoordinate;
    centerCoordinate.latitude = [center[1] doubleValue];
    centerCoordinate.longitude = [center[0] doubleValue];
    [self.mapView setCenterCoordinate:centerCoordinate];
}

- (void)setZoomLevel:(CGFloat)zoom
{
    [self.mapView setZoomLevel:zoom animated:YES];
}


#pragma mark - publish method
- (NSDictionary *)getUserLocation
{
    if(self.mapView.userLocation.updating && self.mapView.userLocation.location) {
        NSArray *coordinate = @[[NSNumber numberWithDouble:self.mapView.userLocation.location.coordinate.longitude],[NSNumber numberWithDouble:self.mapView.userLocation.location.coordinate.latitude]];
        NSDictionary *userDic = @{@"result":@"success",@"data":@{@"position":coordinate,@"title":@""}};
        return userDic;
    }
    return @{@"resuldt":@"false",@"data":@""};
}

#pragma mark - private method
- (void)initPOIData
{
    if (!_annotations) {
        _annotations = [NSMutableDictionary dictionaryWithCapacity:5];
    }
}

- (void)clearPOIData
{
    [_annotations removeAllObjects];
    _annotations = nil;
}

- (MAAnnotationView *)_generateAnnotationView:(MAMapView *)mapView viewForAnnotation:(MAPointAnnotation *)annotation
{
    if (annotation.iconImage){
        static NSString *pointReuseIndetifier = @"customReuseIndetifier";
        MAAnnotationView *annotationView = (MAAnnotationView*)[mapView dequeueReusableAnnotationViewWithIdentifier:pointReuseIndetifier];
        if (annotationView == nil)
        {
            annotationView = [[MAAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:pointReuseIndetifier];
        }
        
        annotationView.canShowCallout               = YES;
        annotationView.draggable                    = YES;
        annotationView.rightCalloutAccessoryView    = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
        [[self imageLoader] downloadImageWithURL:annotation.iconImage imageFrame:CGRectMake(0, 0, 25, 25) userInfo:nil completed:^(UIImage *image, NSError *error, BOOL finished) {
            dispatch_async(dispatch_get_main_queue(), ^{
                annotationView.image = image;
            });
        }];
        return annotationView;
    }else {
        static NSString *pointReuseIndetifier = @"pointReuseIndetifier";
        MAPinAnnotationView *annotationView = (MAPinAnnotationView*)[mapView dequeueReusableAnnotationViewWithIdentifier:pointReuseIndetifier];
        if (annotationView == nil)
        {
            annotationView = [[MAPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:pointReuseIndetifier];
        }
        
        annotationView.canShowCallout               = YES;
        annotationView.draggable                    = YES;
        annotationView.rightCalloutAccessoryView    = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
        return annotationView;
    }
}

#pragma mark - mapview delegate
/*!
 @brief 根据anntation生成对应的View
 */
- (MAAnnotationView*)mapView:(MAMapView *)mapView viewForAnnotation:(id <MAAnnotation>)annotation
{
    if ([annotation isKindOfClass:[MAPointAnnotation class]])
    {
        MAPointAnnotation *pointAnnotation = (MAPointAnnotation *)annotation;
        if ([pointAnnotation.component isKindOfClass:[WXMapInfoWindowComponent class]]) {
            WXMapInfoWindowComponent *infoWindowComponent = (WXMapInfoWindowComponent *)pointAnnotation.component;
            static NSString *customReuseIndetifier = @"customReuseIndetifier";
            WXMapCustomInfoWindow *annotationView = (WXMapCustomInfoWindow*)[mapView dequeueReusableAnnotationViewWithIdentifier:customReuseIndetifier];
            if (annotationView == nil) {
                infoWindowComponent.annotation = annotation;
                infoWindowComponent.identifier = customReuseIndetifier;
                annotationView = infoWindowComponent.view;
                if (infoWindowComponent.subcomponents.count > 0) {
                    for (WXComponent *component in pointAnnotation.component.subcomponents) {
                        [annotationView addCustomView:component.view];
                    }
                }
                annotationView.canShowCallout = NO;
                annotationView.draggable = YES;
                return annotationView;
            }
            
        }else {
            return [self _generateAnnotationView:mapView viewForAnnotation:pointAnnotation];
        }
    }
    
    return nil;
}

/**
 * @brief 当选中一个annotation views时，调用此接口
 * @param mapView 地图View
 * @param view 选中的annotation views
 */
- (void)mapView:(MAMapView *)mapView didSelectAnnotationView:(MAAnnotationView *)view
{
    MAPointAnnotation *annotation = view.annotation;
    for (WXComponent *component in self.subcomponents) {
        if ([component isKindOfClass:[WXMapViewMarkerComponent class]] &&
            [component.ref isEqualToString:annotation.component.ref]) {
            WXMapViewMarkerComponent *marker = (WXMapViewMarkerComponent *)component;
            if (marker.clickEvent) {
                [marker fireEvent:marker.clickEvent params:[NSDictionary dictionary]];
            }
        }
    }
}

/**
 * @brief 当取消选中一个annotation views时，调用此接口
 * @param mapView 地图View
 * @param view 取消选中的annotation views
 */
- (void)mapView:(MAMapView *)mapView didDeselectAnnotationView:(MAAnnotationView *)view
{
    
}

/**
 * @brief 地图移动结束后调用此接口
 * @param mapView       地图view
 * @param wasUserAction 标识是否是用户动作
 */
- (void)mapView:(MAMapView *)mapView mapDidMoveByUser:(BOOL)wasUserAction
{
    if (_isDragend) {
        [self fireEvent:@"dragend" params:[NSDictionary dictionary]];
    }
}

#pragma mark - Overlay
- (MAOverlayRenderer *)mapView:(MAMapView *)mapView rendererForOverlay:(id <MAOverlay>)overlay
{
    if ([overlay isKindOfClass:[MAPolyline class]])
    {
        MAPolyline *polyline = (MAPolyline *)overlay;
        WXMapPolylineComponent *component = polyline.component;
        MAPolylineRenderer *polylineRenderer = [[MAPolylineRenderer alloc] initWithPolyline:overlay];
        polylineRenderer.strokeColor = [WXConvert UIColor:component.strokeColor];
        polylineRenderer.lineWidth   = component.strokeWidth;
        polylineRenderer.lineCapType = kCGLineCapSquare;
        polylineRenderer.lineDash = [WXConvert isLineDash:component.strokeStyle];
        return polylineRenderer;
    }else if ([overlay isKindOfClass:[MAPolygon class]])
    {
        MAPolygon *polygon = (MAPolygon *)overlay;
        WXMapPolygonComponent *component = polygon.component;
        MAPolygonRenderer *polygonRenderer = [[MAPolygonRenderer alloc] initWithPolygon:overlay];
        polygonRenderer.lineWidth   = component.strokeWidth;;
        polygonRenderer.strokeColor = [WXConvert UIColor:component.strokeColor];
        polygonRenderer.fillColor   = [WXConvert UIColor:component.fillColor];
        polygonRenderer.lineDash = [WXConvert isLineDash:component.strokeStyle];
        return polygonRenderer;
    }else if ([overlay isKindOfClass:[MACircle class]])
    {
        MACircle *circle = (MACircle *)overlay;
        WXMapCircleComponent *component = circle.component;
        MACircleRenderer *circleRenderer = [[MACircleRenderer alloc] initWithCircle:overlay];
        circleRenderer.lineWidth   = component.strokeWidth;
        circleRenderer.strokeColor = [WXConvert UIColor:component.strokeColor];
        circleRenderer.fillColor   = [WXConvert UIColor:component.fillColor];
        return circleRenderer;
    }
    
    return nil;
}

@end
