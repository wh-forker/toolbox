% Calculate optical flow using cross-correlation.
%
% Calculate optical flow using correlation, followed by lucas & kanade on
% aligned squares for subpixel accuracy.  Locally, the closest patch within
% some search radius is found.  The distance measure used is the euclidean
% distance between patches -- NOT normalized correlation since we assume
% pixel brightness constancy.  Once the closest matching patch is found,
% the alignment between the two patches is further refined using lucas &
% kanade to find the subpixel translation vector relating the two patches.
%
% This code has been refined for speed, but since it is nonvectorized code
% it can be fairly slow.  Running time is linear in the number of pixels
% but the constant is fairly large.  Test on small image (150x150) before
% running on anything bigger.
%
% USAGE
%  [Vx,Vy,reliab] = optflow_corr( I1, I2, patchR, searchR, 
%                                 [sigma], [thr], [show] )
%
% INPUTS
%  I1, I2      - input images to calculate flow between
%  patchR      - determines correlation patch size around each pixel
%  searchR     - search radius for corresponding patch
%  sigma       - [1] amount to smooth by (may be 0)
%  thr         - [.001] RELATIVE reliability threshold 
%  show        - [0] figure to use for display (no display if == 0)
%
% OUTPUTS
%  Vx, Vy      - x,y components of flow  [Vx>0->right, Vy>0->down]
%  reliab  - reliability of optical flow in given window (cornerness of
%            window)
%
% EXAMPLE
%
% See also OPTFLOW_HORN, OPTFLOW_LUCASKANADE

% Piotr's Image&Video Toolbox      Version 1.5
% Written and maintained by Piotr Dollar    pdollar-at-cs.ucsd.edu
% Please email me if you find bugs, or have suggestions or questions!

function [Vx,Vy,reliab] = optflow_corr( I1, I2, patchR, searchR, ...
                                        sigma, thr, show )

if( nargin<5 || isempty(sigma)); sigma=1; end;
if( nargin<6 || isempty(thr)); thr=0.001; end;
if( nargin<7 || isempty(show)); show=0; end;

% error check inputs
if( ndims(I1)~=2 || ndims(I2)~=2 )
  error('Only works for 2d input images.');
end
if( any(size(I1)~=size(I2)) ) 
  error('Input images must have same dimensions.');
end
if( isa(I1,'uint8')); I1 = double(I1); I2 = double(I2); end;

% smooth images (using the 'smooth' flag causes this to be slow)
I1b = gaussSmooth( I1, [sigma sigma], 'smooth' );
I2b = gaussSmooth( I2, [sigma sigma], 'smooth' );

% precomputed constants
subpixelaccuracy = 1;
siz = size(I1);
big_r = searchR + patchR;
n = (2*patchR+1)^2;
width_D = 2*searchR+1;
[ndxs,ndys] = meshgrid( 1:width_D, 1:width_D );

% hack to penalize more distant translations (closest are best?)
[xs,ys] = meshgrid(-searchR:searchR,-searchR:searchR);
Dpenalty = ((xs.^2 + ys.^2)/searchR^2 + 1) .^(1/20);

% pad I1 and I2 by searchR in each direction
I1b = padarray(I1b,[searchR searchR],0,'both');
I2b = padarray(I2b,[searchR searchR],0,'both');
sizB = size(I1b);

% precompute gradient for subpixel accuracy
[gEy,gEx] = gradient( I1b );

% loop over each window
Vx = zeros( sizB-2*big_r ); Vy = Vx;  reliab = Vx;
for r = big_r+1:sizB(1)-big_r
  for c = big_r+1:sizB(2)-big_r
    T = I1b( r-patchR:r+patchR, c-patchR:c+patchR );
    IC = I2b( r-big_r:r+big_r, c-big_r:c+big_r );

    % get smallest distance
    D = xeuc2_small( T, IC, 'valid' );
    D = (D+eps) .* Dpenalty;
    [disc, ind] = min(D(:));

    % get offset to smallest distance
    ndx = [ndys(ind(1)) ndxs(ind(1))];
    v = ndx - (width_D + 1)/2;

    % get subpixel movement using lucas kanade on rectified windows
    if( subpixelaccuracy )
      T2 = I2b( r+v(1)-patchR:r+v(1)+patchR, c+v(2)-patchR:c+v(2)+ ...
        patchR );
      gEx_rc = gEx(r-patchR:r+patchR, c-patchR:c+patchR );
      gEy_rc = gEy(r-patchR:r+patchR, c-patchR:c+patchR );
      Et_rc = T2-T;
      A = [ gEx_rc(:), gEy_rc(:) ];  b = -Et_rc(:);
      AtA = A'*A;  detAtA = AtA(1)*AtA(4)-AtA(2)*AtA(3);
      if( abs(detAtA) > eps )
        invA = ([AtA(4) -AtA(2); -AtA(3) AtA(1)] / detAtA) * A'; veps = ...
          (invA * b)';
        lambdas = eig(A'*A); subrel = abs(min(lambdas)/max(lambdas));
        if( subrel > .0001 ); v = v + veps; end
      end
    end

    % get reliability
    %Dsort = sort(D(:)); rel = 1 - Dsort(1)/Dsort(2);
    x=T(:); rel = sum(x.*x)/n - (sum(x)/n)^2; % variance

    % record reliability and velocity
    reliab(r-big_r,c-big_r) = rel;
    Vx(r-big_r,c-big_r) = v(2);
    Vy(r-big_r,c-big_r) = v(1);
  end;
end;


% resize all to get rid of padding
Vx = arrayToDims( Vx, siz );
Vy = arrayToDims( Vy, siz );
reliab = arrayToDims( reliab, siz );

% scale reliab to be between [0,1]
reliab = reliab / max([reliab(:); eps]);
Vx(reliab<thr) = 0;  Vy(reliab<thr) = 0;

% show quiver plot on top of reliab
if( show )
  reliab( reliab>1 ) = 1;
  figure(show); clf; im( I1 );
  hold('on'); quiver( Vx, Vy, 0,'-b' ); hold('off');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% since the convolutions are so small just call conv2 everywhere
% see xeucn.m for more general version
function C = xeuc2_small( B, I, shape )
sizB = size(B);
B = rot90( B,2 );
I_mag = localSum( I.*I, sizB, shape );
B_mag = B.^2;  B_mag = sum( B_mag(:) );
C = I_mag + B_mag - 2 * conv2(I,B,shape);


